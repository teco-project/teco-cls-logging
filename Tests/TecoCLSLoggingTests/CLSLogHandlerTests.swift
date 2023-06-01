import XCTest
@testable import TecoCLSLogging
import AsyncHTTPClient
import Logging
import TecoSigner

final class CLSLogHandlerTests: XCTestCase {
    func testLogGroup() throws {
        let data = Data([10, 104, 8, 128, 148, 235, 220, 3, 18, 14, 10, 5, 108, 101, 118, 101, 108, 18, 5, 68, 69, 66, 85, 71, 18, 26, 10, 7, 109, 101, 115, 115, 97, 103, 101, 18, 15, 84, 101, 115, 116, 32, 108, 111, 103, 32, 103, 114, 111, 117, 112, 46, 18, 13, 10, 8, 116, 101, 115, 116, 45, 115, 101, 113, 18, 1, 49, 18, 26, 10, 8, 102, 117, 110, 99, 116, 105, 111, 110, 18, 14, 116, 101, 115, 116, 76, 111, 103, 71, 114, 111, 117, 112, 40, 41, 18, 9, 10, 4, 108, 105, 110, 101, 18, 1, 49, 26, 44, 84, 101, 99, 111, 67, 76, 83, 76, 111, 103, 103, 105, 110, 103, 84, 101, 115, 116, 115, 47, 67, 76, 83, 76, 111, 103, 72, 97, 110, 100, 108, 101, 114, 84, 101, 115, 116, 115, 46, 115, 119, 105, 102, 116, 34, 19, 84, 101, 99, 111, 67, 76, 83, 76, 111, 103, 103, 105, 110, 103, 84, 101, 115, 116, 115])
        let logGroup = Cls_LogGroup(
            .debug,
            message: "Test log group.",
            metadata: ["test-seq": "1"],
            source: "TecoCLSLoggingTests",
            file: "TecoCLSLoggingTests/CLSLogHandlerTests.swift",
            function: "testLogGroup()",
            line: 1,
            date: Date(timeIntervalSince1970: 1_000_000_000)
        )
        XCTAssertEqual(try logGroup.serializedData(), data)
    }
    
    func testResolveMetadata() throws {
        // create logger
        var logger = CLSLogHandler(
            client: .init(eventLoopGroupProvider: .createNew),
            credentialProvider: { StaticCredential(secretId: "", secretKey: "") },
            region: "ap-guangzhou",
            topicID: "xxxxxxxx-xxxx-xxxx-xxxx"
        )
        defer {
            try? logger.client.client.syncShutdown()
            try? logger.accumulator.syncShutdown()
        }
        
        // set up metadata provider
        logger.metadataProvider = Logger.MetadataProvider {
            [
                "provider-specific": "included",
                "logger-provided": .dictionary(["source": "metadata-provider"]),
                "overlapping-source": "provider",
            ]
        }
        // set up logger metadata
        logger[metadataKey: "logger-specific"] = "included"
        logger[metadataKey: "logger-provided"] = .dictionary(["source": "logger"])
        logger[metadataKey: "overlapping-source"] = "logger"
        // set up log message metadata
        let metadata: Logger.Metadata = [
            "message-specific": "included",
            "overlapping-source": "message",
        ]
        
        // assert resolved metadata
        let resolved = logger.resolveMetadata(metadata)
        // overlapping key should be resolved from message
        XCTAssertEqual(resolved["overlapping-source"], "message")
        // logger metadata should percede metadata provider
        XCTAssertEqual(resolved["logger-provided"], ["source": "logger"])
        // all three sources should be taken into account
        for source in ["provider", "logger", "message"] {
            XCTAssertEqual(resolved["\(source)-specific"], "included")
        }
    }
    
    func testUploadRequest() throws {
        // create log client
        let client = CLSLogClient(
            client: .init(eventLoopGroupProvider: .createNew),
            credentialProvider: { StaticCredential(secretId: "", secretKey: "") },
            region: "ap-guangzhou",
            topicID: "xxxxxxxx-xxxx-xxxx-xxxx"
        )
        defer { try? client.client.syncShutdown() }
        
        // build log group
        let date = Date(timeIntervalSince1970: 1_000_000_000)
        let logGroupList = Cls_LogGroupList([
            Cls_LogGroup(
                .info,
                message: "Test upload request.",
                source: "TecoCLSLoggingTests",
                file: "TecoCLSLoggingTests/CLSLogHandlerTests.swift",
                function: "testUploadRequest()",
                line: 1,
                date: date
            )
        ])
        
        // build and assert request basics
        let credential = StaticCredential(
            secretId: "AKIDz8krbsJ5yKBZQpn74WFkmLPx3EXAMPLE",
            secretKey: "Gu5t9xGARNpq86cd98joQYCN3EXAMPLE"
        )
        // test with minimal signing here in case new headers are added
        let request = try client.uploadLogRequest(logGroupList, credential: credential, date: date, signing: .minimal)
        XCTAssertEqual(request.method, .POST)
        
        // assert request headers
        XCTAssertEqual(request.headers.first(name: "content-type"), "application/octet-stream")
        XCTAssertEqual(request.headers.first(name: "host"), "cls.tencentcloudapi.com")
        XCTAssertEqual(request.headers.first(name: "x-cls-topicid"), "xxxxxxxx-xxxx-xxxx-xxxx")
        XCTAssertEqual(request.headers.first(name: "x-tc-action"), "UploadLog")
        XCTAssertEqual(request.headers.first(name: "x-tc-version"), "2020-10-16")
        XCTAssertEqual(request.headers.first(name: "x-tc-region"), "ap-guangzhou")
        XCTAssertEqual(
            request.headers.first(name: "authorization"),
            "TC3-HMAC-SHA256 Credential=AKIDz8krbsJ5yKBZQpn74WFkmLPx3EXAMPLE/2001-09-09/cls/tc3_request, SignedHeaders=content-type;host, Signature=4650f896956144eae9f5bafbd14f8ad6c62dea02ea297d280658468fb3cac765"
        )
    }
    
    func testLoggingSystem() throws {
        // set up test helpers
        let data = Data([10, 180, 1, 10, 111, 8, 128, 148, 235, 220, 3, 18, 13, 10, 5, 108, 101, 118, 101, 108, 18, 4, 73, 78, 70, 79, 18, 20, 10, 7, 109, 101, 115, 115, 97, 103, 101, 18, 9, 84, 101, 115, 116, 32, 73, 78, 70, 79, 18, 27, 10, 9, 116, 101, 115, 116, 45, 105, 116, 101, 109, 18, 14, 108, 111, 103, 103, 105, 110, 103, 45, 115, 121, 115, 116, 101, 109, 18, 26, 10, 8, 102, 117, 110, 99, 116, 105, 111, 110, 18, 14, 116, 101, 115, 116, 76, 111, 103, 71, 114, 111, 117, 112, 40, 41, 18, 9, 10, 4, 108, 105, 110, 101, 18, 1, 49, 26, 44, 84, 101, 99, 111, 67, 76, 83, 76, 111, 103, 103, 105, 110, 103, 84, 101, 115, 116, 115, 47, 67, 76, 83, 76, 111, 103, 72, 97, 110, 100, 108, 101, 114, 84, 101, 115, 116, 115, 46, 115, 119, 105, 102, 116, 34, 19, 84, 101, 99, 111, 67, 76, 83, 76, 111, 103, 103, 105, 110, 103, 84, 101, 115, 116, 115, 10, 205, 1, 10, 135, 1, 8, 128, 148, 235, 220, 3, 18, 14, 10, 5, 108, 101, 118, 101, 108, 18, 5, 69, 82, 82, 79, 82, 18, 21, 10, 7, 109, 101, 115, 115, 97, 103, 101, 18, 10, 84, 101, 115, 116, 32, 69, 82, 82, 79, 82, 18, 27, 10, 9, 116, 101, 115, 116, 45, 105, 116, 101, 109, 18, 14, 108, 111, 103, 103, 105, 110, 103, 45, 115, 121, 115, 116, 101, 109, 18, 20, 10, 6, 114, 101, 97, 115, 111, 110, 18, 10, 116, 101, 115, 116, 32, 101, 114, 114, 111, 114, 18, 26, 10, 8, 102, 117, 110, 99, 116, 105, 111, 110, 18, 14, 116, 101, 115, 116, 76, 111, 103, 71, 114, 111, 117, 112, 40, 41, 18, 9, 10, 4, 108, 105, 110, 101, 18, 1, 50, 26, 44, 84, 101, 99, 111, 67, 76, 83, 76, 111, 103, 103, 105, 110, 103, 84, 101, 115, 116, 115, 47, 67, 76, 83, 76, 111, 103, 72, 97, 110, 100, 108, 101, 114, 84, 101, 115, 116, 115, 46, 115, 119, 105, 102, 116, 34, 19, 84, 101, 99, 111, 67, 76, 83, 76, 111, 103, 103, 105, 110, 103, 84, 101, 115, 116, 115, 10, 186, 1, 10, 117, 8, 128, 148, 235, 220, 3, 18, 16, 10, 5, 108, 101, 118, 101, 108, 18, 7, 87, 65, 82, 78, 73, 78, 71, 18, 23, 10, 7, 109, 101, 115, 115, 97, 103, 101, 18, 12, 84, 101, 115, 116, 32, 87, 65, 82, 78, 73, 78, 71, 18, 27, 10, 9, 116, 101, 115, 116, 45, 105, 116, 101, 109, 18, 14, 108, 111, 103, 103, 105, 110, 103, 45, 115, 121, 115, 116, 101, 109, 18, 26, 10, 8, 102, 117, 110, 99, 116, 105, 111, 110, 18, 14, 116, 101, 115, 116, 76, 111, 103, 71, 114, 111, 117, 112, 40, 41, 18, 9, 10, 4, 108, 105, 110, 101, 18, 1, 51, 26, 44, 84, 101, 99, 111, 67, 76, 83, 76, 111, 103, 103, 105, 110, 103, 84, 101, 115, 116, 115, 47, 67, 76, 83, 76, 111, 103, 72, 97, 110, 100, 108, 101, 114, 84, 101, 115, 116, 115, 46, 115, 119, 105, 102, 116, 34, 19, 84, 101, 99, 111, 67, 76, 83, 76, 111, 103, 103, 105, 110, 103, 84, 101, 115, 116, 115])
        func upload(_ logs: any Collection<Cls_LogGroup>) throws -> String {
            let logs = logs.map { logGroup in
                var logGroup = logGroup
                logGroup.logs = logGroup.logs.map { log in
                    var log = log
                    log.time = 1_000_000_000
                    return log
                }
                return logGroup
            }
            let logGroupList = Cls_LogGroupList(logs)
            XCTAssertTrue(logGroupList.isInitialized)
            XCTAssertEqual(try logGroupList.serializedData(), data)
            return "mock-upload-id"
        }
        
        // create log handler with custom accumulator
        let logHandler = CLSLogHandler(
            client: .init(
                client: .init(eventLoopGroupProvider: .createNew),
                credentialProvider: { StaticCredential(secretId: "", secretKey: "") },
                region: "ap-guangzhou",
                topicID: "xxxxxxxx-xxxx-xxxx-xxxx"
            ),
            accumulator: .init(batchSize: 4, uploader: upload)
        )
        
        // we're not actually sending any requests here
        try logHandler.client.client.syncShutdown()
        
        // bootstrap log handler
        LoggingSystem.bootstrap({ _ in logHandler })
        let logger = Logger(label: "test", metadataProvider: .init({ ["test-item" : "logging-system"] }))
        
        // send in batch
        logger.info(
            "Test INFO",
            source: "TecoCLSLoggingTests",
            file: "TecoCLSLoggingTests/CLSLogHandlerTests.swift",
            function: "testLogGroup()",
            line: 1
        )
        logger.error(
            "Test ERROR",
            metadata: ["reason" : "test error"],
            source: "TecoCLSLoggingTests",
            file: "TecoCLSLoggingTests/CLSLogHandlerTests.swift",
            function: "testLogGroup()",
            line: 2
        )
        logger.warning(
            "Test WARNING",
            source: "TecoCLSLoggingTests",
            file: "TecoCLSLoggingTests/CLSLogHandlerTests.swift",
            function: "testLogGroup()",
            line: 3
        )
        
        // shut down the log handler should send all pending logs
        try logHandler.accumulator.syncShutdown()
    }
}
