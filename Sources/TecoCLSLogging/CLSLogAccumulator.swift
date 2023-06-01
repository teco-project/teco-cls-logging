import Dispatch
import struct NIOConcurrencyHelpers.NIOLock

class CLSLogAccumulator {

    private var lock: NIOLock = .init()
    private var logs: [Cls_LogGroup] = []
    private var deadline: DispatchWallTime = .distantFuture
    private var isShutdown = false

    let maxBatchSize: Int
    let maxWaitNanoseconds: Int?
    let uploader: ([Cls_LogGroup]) async throws -> String

    init(maxBatchSize: UInt, maxWaitNanoseconds: UInt?, uploader: @escaping ([Cls_LogGroup]) async throws -> String) {
        self.maxBatchSize = Int(maxBatchSize)
        if let maxWaitNanoseconds = maxWaitNanoseconds {
            self.maxWaitNanoseconds = Int(maxWaitNanoseconds)
        } else {
            self.maxWaitNanoseconds = nil
        }
        self.uploader = uploader
    }

    func shutdown() async throws {
        precondition(self.isShutdown == false)
        while !self.logs.isEmpty {
            try await self.uploadLogs()
        }
        self.isShutdown = true
    }

    func addLog(_ log: Cls_LogGroup) {
        // set deadline and append log
        self.lock.withLock {
            if let maxWaitNanoseconds = maxWaitNanoseconds {
                let deadline = DispatchWallTime.now() + .nanoseconds(maxWaitNanoseconds)
                if self.deadline > deadline {
                    self.deadline = deadline
                }
            }
            self.logs.append(log)
        }

        // upload if required
        Task {
            if self.shouldUpload {
                _ = try await self.uploadLogs()
            }
        }
    }

    private func uploadLogs() async throws {
        // fetch batch logs
        var batch: [Cls_LogGroup] = []
        self.lock.withLock {
            batch = self.logs.prefix(maxBatchSize).map({ $0 })
            self.logs.removeFirst(batch.count)
            self.deadline = .distantFuture
        }

        // don't continue with empty log
        guard !batch.isEmpty else {
            return
        }

        // upload logs
        let requestID = try await uploader(.init(batch))
        #if DEBUG
        print("CLS logs sent with request ID: \(requestID)")
        #else
        _ = requestID
        #endif
    }

    private var shouldUpload: Bool {
        return logs.count >= maxBatchSize || deadline < .now()
    }
}

extension CLSLogAccumulator {
    func syncShutdown() throws {
        let errorStorageLock = NIOLock()
        let errorStorage: UnsafeMutableTransferBox<Error?> = .init(nil)
        let continuation = DispatchWorkItem {}
        Task.detached {
            do {
                try await self.shutdown()
            } catch {
                errorStorageLock.withLock {
                    errorStorage.wrappedValue = error
                }
            }
            continuation.perform()
        }
        continuation.wait()
        try errorStorageLock.withLock {
            if let error = errorStorage.wrappedValue {
                throw error
            }
        }
    }
}
