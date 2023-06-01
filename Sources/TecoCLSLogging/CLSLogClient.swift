import AsyncHTTPClient
import struct Foundation.Date
import TecoSigner

public struct CLSLogClient {

    public let client: HTTPClient
    public let region: String
    public let topicID: String

    internal let credentialProvider: () -> Credential

    public init(client: HTTPClient, credentialProvider: @escaping () -> Credential, region: String, topicID: String) {
        self.client = client
        self.credentialProvider = credentialProvider
        self.region = region
        self.topicID = topicID
    }

    // MARK: Internal implemenation

    func uploadLogs(_ logs: any Collection<Cls_LogGroup>) async throws -> String {
        let logGroupList = Cls_LogGroupList(logs)
        let request = try self.uploadLogRequest(logGroupList, credential: self.credentialProvider())

        struct TCResponse: Decodable {
            struct Response: Decodable {
                let RequestId: String
            }
            let Response: Response
        }

        let response = try await self.client.execute(request, timeout: .seconds(3))
        var body = try await response.body.collect(upTo: 1024 * 1024)

        guard let response = try body.readJSONDecodable(TCResponse.self, length: body.readableBytes) else {
            throw Error.malformedResponse
        }
        return response.Response.RequestId
    }

    func uploadLogRequest(_ logGroupList: Cls_LogGroupList, credential: Credential, date: Date = Date(), signing: TCSigner.SigningMode = .default) throws -> HTTPClientRequest {
        assert(logGroupList.isInitialized)

        let signer = TCSigner(credential: credential, service: "cls")
        let data = try logGroupList.serializedData()

        var request = HTTPClientRequest(url: "https://cls.tencentcloudapi.com")
        request.method = .POST
        request.headers = try signer.signHeaders(
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
        request.body = .bytes(data)

        return request
    }

    // MARK: Errors

    enum Error: Swift.Error {
        case malformedResponse
    }
}
