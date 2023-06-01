import Dispatch
import struct NIOConcurrencyHelpers.NIOLock

class CLSLogAccumulator {

    private var lock: NIOLock = .init()
    private var logQueue: [Cls_LogGroup] = []
    private var deadline: DispatchWallTime = .distantFuture

    let maxBatchSize: Int
    let maxWaitTime: DispatchTimeInterval?
    let uploader: ([Cls_LogGroup]) async throws -> String

    init(maxBatchSize: UInt, maxWaitNanoseconds: UInt?, uploader: @escaping ([Cls_LogGroup]) async throws -> String) {
        self.maxBatchSize = Int(maxBatchSize)
        if let maxWaitNanoseconds = maxWaitNanoseconds {
            self.maxWaitTime = .nanoseconds(Int(maxWaitNanoseconds))
        } else {
            self.maxWaitTime = nil
        }
        self.uploader = uploader
    }

    deinit {
        try? self.forceFlush()
    }

    func forceFlush() throws {
        let errorStorageLock = NIOLock()
        let errorStorage: UnsafeMutableTransferBox<Error?> = .init(nil)
        let continuation = DispatchWorkItem {}
        Task.detached {
            do {
                while let payload = self.batchUploadPayload(force: true) {
                    _ = try await self.uploader(payload)
                }
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

    func addLog(_ log: Cls_LogGroup) {
        // set deadline and append log
        self.lock.withLock {
            if let maxWaitTime = maxWaitTime {
                let deadline = DispatchWallTime.now() + maxWaitTime
                if self.deadline > deadline {
                    self.deadline = deadline
                }
            }
            self.logQueue.append(log)
        }

        // upload if required
        if let payload = self.batchUploadPayload() {
            Task.detached {
                _ = try await self.uploader(payload)
            }
        }
    }

    private func batchUploadPayload(force: Bool = false) -> [Cls_LogGroup]? {
        // get log queue length
        guard !logQueue.isEmpty else {
            return nil
        }
        let queued = logQueue.count
        assert(queued > 0)

        // compute batch size
        guard queued >= maxBatchSize || deadline < .now() || force else {
            return nil
        }
        let batchSize = min(queued, maxBatchSize)
        assert(logQueue.count >= batchSize)

        // dequeue the batch
        return self.lock.withLock {
            let batch = self.logQueue.prefix(batchSize)
            assert(batch.count == batchSize)
            self.logQueue.removeFirst(batchSize)

            if !self.logQueue.isEmpty, let maxWaitTime = maxWaitTime  {
                self.deadline = .now() + maxWaitTime
            } else {
                self.deadline = .distantFuture
            }
            return .init(batch)
        }
    }
}
