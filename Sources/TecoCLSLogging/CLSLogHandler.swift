import AsyncHTTPClient
import Foundation
import Logging
import NIOHTTP1
import TecoSigner

public struct CLSLogHandler: LogHandler {

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

    // MARK: Log handler implemenation

    public var logLevel: Logger.Level = .info
    public var metadata: Logger.Metadata = .init()
    public var metadataProvider: Logger.MetadataProvider?

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get {
            metadata[key]
        }
        set {
            metadata[key] = newValue
        }
    }

    public func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
        let metadata = resolveMetadata(metadata)
        let log = Cls_LogGroup(level, message: message, metadata: metadata, source: source, file: file, function: function, line: line)
        precondition(log.isInitialized)
        if let request = try? self.uploadLogRequest(log, credential: self.credentialProvider()) {
            Task.detached {
                try await self.client.execute(request, timeout: .seconds(3))
            }
        }
    }

    // MARK: Internal implemenation

    func resolveMetadata(_ metadata: Logger.Metadata?) -> Logger.Metadata {
        return (metadataProvider?.get() ?? [:])
            .merging(self.metadata, uniquingKeysWith: { $1 })
            .merging(metadata ?? [:], uniquingKeysWith: { $1 })
    }

    func uploadLogRequest(_ logGroup: Cls_LogGroup, credential: Credential, date: Date = Date(), signing: TCSigner.SigningMode = .default) throws -> HTTPClientRequest {
        let logGroupList = Cls_LogGroupList.with {
            $0.logGroupList = [logGroup]
        }
        precondition(logGroupList.isInitialized)

        let signer = TCSigner(credential: credential, service: "cls")
        let data = try logGroupList.serializedData()

        var request = HTTPClientRequest(url: "https://cls.tencentcloudapi.com")
        guard let url = URL(string: request.url) else {
            throw HTTPClientError.invalidURL
        }
        request.method = .POST
        request.body = .bytes(data)
        request.headers = signer.signHeaders(
            url: url,
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
