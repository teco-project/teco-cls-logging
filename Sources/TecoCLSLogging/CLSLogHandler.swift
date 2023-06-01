import class AsyncHTTPClient.HTTPClient
import Logging
import protocol TecoSigner.Credential

public struct CLSLogHandler: LogHandler {

    public let client: CLSLogClient
    public let queue: CLSLogQueue

    public init(
        client: HTTPClient,
        credentialProvider: @escaping () -> Credential,
        region: String,
        topicID: String,
        queueConfig: CLSLogQueue.Configuration = .init()
    ) {
        self.client = .init(client: client, credentialProvider: credentialProvider, region: region, topicID: topicID)
        self.queue = .init(configuration: queueConfig, uploader: self.client.uploadLogs)
    }

    // MARK: Log handler implemenation

    public var logLevel: Logger.Level = .info
    public var metadata: Logger.Metadata = .init()
    public var metadataProvider: Logger.MetadataProvider?

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get {
            self.metadata[key]
        }
        set {
            self.metadata[key] = newValue
        }
    }

    public func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
        let metadata = self.resolveMetadata(metadata)
        let log = Cls_LogGroup(level, message: message, metadata: metadata, source: source, file: file, function: function, line: line)
        assert(log.isInitialized)
        self.queue.enqueue(log)
    }

    // MARK: Internal implemenation

    func resolveMetadata(_ metadata: Logger.Metadata?) -> Logger.Metadata {
        return (self.metadataProvider?.get() ?? [:])
            .merging(self.metadata, uniquingKeysWith: { $1 })
            .merging(metadata ?? [:], uniquingKeysWith: { $1 })
    }

    // MARK: Test utility

    internal init(client: CLSLogClient, queue: CLSLogQueue) {
        self.client = client
        self.queue = queue
    }
}
