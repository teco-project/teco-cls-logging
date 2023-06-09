import XCTest
@testable import TecoCLSLogging
import AsyncHTTPClient
import TecoSigner

final class CLSLogClientTests: XCTestCase {
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
}
