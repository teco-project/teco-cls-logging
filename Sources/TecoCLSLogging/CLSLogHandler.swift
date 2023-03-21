import Logging
import Foundation
import TecoSigner
import AsyncHTTPClient
import NIOHTTP1

public struct CLSLogHandler: LogHandler {
    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get {
            metadata[key]
        }
        set {
            metadata[key] = newValue
        }
    }

    public var metadata: Logger.Metadata = .init()
    public var logLevel: Logger.Level = .info

    public let client: HTTPClient
    public let credentialProvider: () -> Credential
    public let region: String
    public let topicID: String

    public init(client: HTTPClient, credentialProvider: @escaping () -> Credential, region: String, topicID: String) {
        self.client = client
        self.credentialProvider = credentialProvider
        self.region = region
        self.topicID = topicID
    }

    public func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
        let log = Cls_LogGroup(level, message: message, metadata: metadata, source: source, file: file, function: function, line: line)
        precondition(log.isInitialized)
        if let request = try? self.uploadLogRequest(log, credential: self.credentialProvider()) {
            _ = try? self.client.execute(request: request).wait()
        }
    }

    func uploadLogRequest(_ logGroup: Cls_LogGroup, credential: Credential, date: Date = Date(), signing: TCSigner.SigningMode = .default) throws -> HTTPClient.Request {
        let logGroupList = Cls_LogGroupList.with {
            $0.logGroupList = [logGroup]
        }
        precondition(logGroupList.isInitialized)

        let signer = TCSigner(credential: credential, service: "cls")
        let data = try logGroupList.serializedData()

        var request = try HTTPClient.Request(
            url: "https://cls.tencentcloudapi.com",
            method: .POST,
            body: .data(data)
        )
        request.headers = signer.signHeaders(
            url: request.url,
            method: request.method,
            headers: [
                "content-type": "application/octet-stream",
                "x-tc-action": "UploadLog",
                "x-tc-version": "2020-10-16",
                "x-tc-region": self.region,
                "x-cls-topicid": self.topicID
            ],
            body: .data(data),
            mode: signing,
            date: date
        )

        return request
    }
}
