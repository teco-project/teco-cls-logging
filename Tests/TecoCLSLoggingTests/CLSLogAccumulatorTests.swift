import XCTest
@testable import TecoCLSLogging
import AsyncHTTPClient
import Atomics

final class CLSLogAccumulatorTests: XCTestCase {
    func testBatchSize() async throws {
        // set up test helpers
        let batches = ManagedAtomic(0)
        func upload(_ logs: [Cls_LogGroup]) throws -> String {
            XCTAssertLessThanOrEqual(logs.count, 2)
            batches.wrappingIncrement(ordering: .relaxed)
            return "mock-upload-id"
        }

        // create log accumulator
        let accumulator = CLSLogAccumulator(
            maxBatchSize: 2,
            maxWaitNanoseconds: nil,
            uploader: upload
        )

        // test adding logs
        for id in 0...10 {
            accumulator.addLog(
                .init(.debug, message: "Hello with ID#\(id)",
                      source: "TecoCLSLoggingTests",
                      file: #fileID, function: #function, line: #line)
            )
        }

        // force flush the logger to upload logs
        try accumulator.forceFlush()

        // assert batch counts
        XCTAssertEqual(batches.load(ordering: .acquiring), 6)
    }

    func testWaitDuration() async throws {
        // set up test helpers
        func upload(_ logs: [Cls_LogGroup]) throws -> String {
            XCTAssertLessThanOrEqual(logs.count, 3)
            return "mock-upload-id"
        }

        // create log accumulator
        let accumulator = CLSLogAccumulator(
            maxBatchSize: 5,
            maxWaitNanoseconds: 200_000_000,
            uploader: upload
        )

        // test adding logs
        for id in 0...10 {
            accumulator.addLog(
                .init(.debug, message: "Hello with ID#\(id)",
                      source: "TecoCLSLoggingTests",
                      file: #fileID, function: #function, line: #line)
            )
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
