import Dispatch
import struct NIOConcurrencyHelpers.NIOLock

actor CLSLogAccumulator {

    private var logs: [Cls_LogGroup] = []
    private var deadline: DispatchWallTime = .distantFuture
    private var isShutdown = false

    nonisolated let maxBatchSize: Int
    nonisolated let maxWaitNanoseconds: Int?
    nonisolated let uploader: ([Cls_LogGroup]) async throws -> String

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
            _ = try await self.uploadLogs()
        }
        self.isShutdown = true
    }

    func addLog(_ log: Cls_LogGroup) async throws {
        // set deadline
        if let maxWaitNanoseconds = maxWaitNanoseconds {
            let deadline = DispatchWallTime.now() + .nanoseconds(maxWaitNanoseconds)
            if self.deadline > deadline {
                self.deadline = deadline
            }
        }

        // append and upload
        self.logs.append(log)
        if self.shouldUpload {
            _ = try await self.uploadLogs()
        }
    }

    private func uploadLogs() async throws -> String {
        // fetch batch logs
        let batch = self.logs.prefix(maxBatchSize)
        self.logs.removeFirst(batch.count)
        self.deadline = .distantFuture

        // upload logs
        let requestID = try await uploader(.init(batch))
        #if DEBUG
        print("CLS logs sent with request ID: \(requestID)")
        #endif
        return requestID
    }

    private var shouldUpload: Bool {
        return logs.count >= maxBatchSize || deadline < .now()
    }
}

extension CLSLogAccumulator {
    nonisolated func syncShutdown() throws {
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
