import XCTest
@testable import TecoCLSLogging
import AsyncHTTPClient
import Logging
import NIOFoundationCompat
import TecoSigner

final class CLSLogHandlerTests: XCTestCase {
    func testLogGroup() throws {
        let data = Data([10, 105, 8, 128, 148, 235, 220, 3, 18, 14, 10, 5, 108, 101, 118, 101, 108, 18, 5, 68, 69, 66, 85, 71, 18, 26, 10, 7, 109, 101, 115, 115, 97, 103, 101, 18, 15, 84, 101, 115, 116, 32, 108, 111, 103, 32, 103, 114, 111, 117, 112, 46, 18, 13, 10, 8, 116, 101, 115, 116, 45, 115, 101, 113, 18, 1, 49, 18, 26, 10, 8, 102, 117, 110, 99, 116, 105, 111, 110, 18, 14, 116, 101, 115, 116, 76, 111, 103, 71, 114, 111, 117, 112, 40, 41, 18, 10, 10, 4, 108, 105, 110, 101, 18, 2, 49, 48, 26, 44, 84, 101, 99, 111, 67, 76, 83, 76, 111, 103, 103, 105, 110, 103, 84, 101, 115, 116, 115, 47, 67, 76, 83, 76, 111, 103, 72, 97, 110, 100, 108, 101, 114, 84, 101, 115, 116, 115, 46, 115, 119, 105, 102, 116, 34, 19, 84, 101, 99, 111, 67, 76, 83, 76, 111, 103, 103, 105, 110, 103, 84, 101, 115, 116, 115])
        let logGroup = Cls_LogGroup(
            .debug,
            message: "Test log group.",
            metadata: ["test-seq": "1"],
            source: "TecoCLSLoggingTests",
            file: "TecoCLSLoggingTests/CLSLogHandlerTests.swift",
            function: "testLogGroup()",
            line: 10,
            date: Date(timeIntervalSince1970: 1_000_000_000)
        )
        XCTAssertEqual(data, try logGroup.serializedData())
    }

    func testResolveMetadata() throws {
        // create logger
        var logger = CLSLogHandler(
            client: .init(eventLoopGroupProvider: .createNew),
            credentialProvider: { StaticCredential(secretId: "", secretKey: "") },
            region: "ap-guangzhou",
            topicID: "xxxxxxxx-xxxx-xxxx-xxxx"
        )
        defer { try? logger.client.syncShutdown() }

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
        // create logger
        let logger = CLSLogHandler(
            client: .init(eventLoopGroupProvider: .createNew),
            credentialProvider: { StaticCredential(secretId: "", secretKey: "") },
            region: "ap-guangzhou",
            topicID: "xxxxxxxx-xxxx-xxxx-xxxx"
        )
        defer { try? logger.client.syncShutdown() }

        // build log group
        let date =  Date(timeIntervalSince1970: 1_000_000_000)
        let logGroup = Cls_LogGroup(
            .info,
            message: "Test upload request.",
            metadata: ["test-seq": "2"],
            source: "TecoCLSLoggingTests",
            file: "TecoCLSLoggingTests/CLSLogHandlerTests.swift",
            function: "testUploadRequest()",
            line: 35,
            date: date
        )

        // build and assert request basics
        let credential = StaticCredential(
            secretId: "AKIDz8krbsJ5yKBZQpn74WFkmLPx3EXAMPLE",
            secretKey: "Gu5t9xGARNpq86cd98joQYCN3EXAMPLE"
        )
        // test with minimal signing here in case new headers are added
        let request = try logger.uploadLogRequest(logGroup, credential: credential, date: date, signing: .minimal)
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
            "TC3-HMAC-SHA256 Credential=AKIDz8krbsJ5yKBZQpn74WFkmLPx3EXAMPLE/2001-09-09/cls/tc3_request, SignedHeaders=content-type;host, Signature=1249e1b231a7a1c5d840c2c36d5e832a20671ab370256120fb6c1c9d26d28d12"
        )
    }
}
