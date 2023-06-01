import XCTest
@testable import TecoCLSLogging
import Logging
import TecoSigner

final class CLSLogHandlerTests: XCTestCase {
    func testResolveMetadata() throws {
        // create logger
        var logger = CLSLogHandler(
            client: .init(eventLoopGroupProvider: .createNew),
            credentialProvider: { StaticCredential(secretId: "", secretKey: "") },
            region: "ap-guangzhou",
            topicID: "xxxxxxxx-xxxx-xxxx-xxxx"
        )
        defer { try? logger.client.client.syncShutdown() }

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

    func testLogger() throws {
        // set up test helpers
        func upload(_ logs: [Cls_LogGroup]) throws -> String {
            let logGroupList = Cls_LogGroupList(logs)
            XCTAssertTrue(logGroupList.isInitialized)
            XCTAssertEqual(logs.count, 3)
            return "mock-upload-id"
        }

        // create log handler with custom queue
        let logHandler = CLSLogHandler(
            client: .init(
                client: .init(eventLoopGroupProvider: .createNew),
                credentialProvider: { StaticCredential(secretId: "", secretKey: "") },
                region: "ap-guangzhou",
                topicID: "xxxxxxxx-xxxx-xxxx-xxxx"
            ),
            queue: .init(configuration: .init(maxBatchSize: 3), uploader: upload)
        )

        // we're not actually sending any requests here
        try logHandler.client.client.syncShutdown()

        // test with logger
        let logger = Logger(label: "test", factory: { _ in logHandler })
        logger.info("Test 1")
        logger.error("Test 2", metadata: ["reason" : "test error"])
        logger.warning("Test 3")
    }
}
