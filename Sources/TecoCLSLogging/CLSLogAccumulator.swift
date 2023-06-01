import class Dispatch.DispatchWorkItem
import struct NIOConcurrencyHelpers.NIOLock

actor CLSLogAccumulator {

    private var logs: [Cls_LogGroup] = []
    private var isShutdown = false

    nonisolated let batchSize: Int
    nonisolated let uploader: (any Collection<Cls_LogGroup>) async throws -> String

    init(batchSize: UInt, uploader: @escaping (any Collection<Cls_LogGroup>) async throws -> String) {
        self.batchSize = Int(batchSize)
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
        self.logs.append(log)
        if self.shouldUpload {
            _ = try await self.uploadLogs()
        }
    }

    private func uploadLogs() async throws -> String {
        let batch = self.logs.prefix(batchSize)
        self.logs.removeFirst(batch.count)
        let requestID = try await uploader(batch)
        #if DEBUG
        print("CLS logs sent with request ID: \(requestID)")
        #endif
        return requestID
    }

    private var shouldUpload: Bool {
        return logs.count >= batchSize
    }
}

extension CLSLogAccumulator {
    @available(*, noasync)
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
