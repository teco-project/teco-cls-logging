import Logging
import Foundation

extension Cls_LogGroup {
    init(_ level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt, date: Date = Date()) {
        self = Self.with {
            $0.source = source
            $0.filename = file
            $0.logs = [
                .init(level, message: message, metadata: metadata, function: function, line: line, date: date)
            ]
        }
    }
}

extension Cls_Log {
    init(_ level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, function: String, line: UInt, date: Date) {
        self = Self.with {
            var contents: [Content] = []
            contents.append(.init(key: "level", value: level.rawValue.uppercased()))
            contents.append(.init(key: "message", value: .stringConvertible(message)))
            contents.append(contentsOf: metadata?.map(Content.init) ?? [])
            contents.append(.init(key: "function", value: function))
            contents.append(.init(key: "line", value: .stringConvertible(line)))
            $0.contents = contents
            $0.time = .init(date.timeIntervalSince1970)
        }
    }
}

extension Cls_Log.Content {
    init(key: String, value: String) {
        self = Self.with {
            $0.key = key
            $0.value = value
        }
    }

    init(key: String, value: Logger.MetadataValue) {
        self.init(key: key, value: value.description)
    }
}
