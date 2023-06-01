import Dispatch
import struct NIOConcurrencyHelpers.NIOLock

public class CLSLogQueue {

    private var lock: NIOLock = .init()
    private var logs: [Cls_LogGroup] = []
    private var deadline: DispatchWallTime = .distantFuture

    public let configuration: Configuration

    public struct Configuration {
        public let maxBatchSize: Int
        public let maxWaitTime: DispatchTimeInterval?

        public init(maxBatchSize: UInt = 4, maxWaitNanoseconds: UInt? = nil) {
            self.maxBatchSize = Int(maxBatchSize)
            if let maxWaitNanoseconds = maxWaitNanoseconds {
                self.maxWaitTime = .nanoseconds(Int(maxWaitNanoseconds))
            } else {
                self.maxWaitTime = nil
            }
        }
    }

    private let uploader: ([Cls_LogGroup]) async throws -> String

    init(configuration: Configuration = .init(), uploader: @escaping ([Cls_LogGroup]) async throws -> String) {
        self.configuration = configuration
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

    func enqueue(_ log: Cls_LogGroup) {
        // set deadline and append log
        self.lock.withLock {
            if let maxWaitTime = configuration.maxWaitTime {
                let deadline = DispatchWallTime.now() + maxWaitTime
                if self.deadline > deadline {
                    self.deadline = deadline
                }
            }
            self.logs.append(log)
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
        guard !logs.isEmpty else {
            return nil
        }
        let queued = logs.count
        assert(queued > 0)

        // compute batch size
        guard queued >= configuration.maxBatchSize || deadline < .now() || force else {
            return nil
        }
        let batchSize = min(queued, configuration.maxBatchSize)
        assert(logs.count >= batchSize)

        // dequeue the batch
        return self.lock.withLock {
            let batch = self.logs.prefix(batchSize)
            assert(batch.count == batchSize)
            self.logs.removeSubrange(batch.indices)

            if !self.logs.isEmpty, let maxWaitTime = configuration.maxWaitTime {
                self.deadline = .now() + maxWaitTime
            } else {
                self.deadline = .distantFuture
            }
            return .init(batch)
        }
    }
}
