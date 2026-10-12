import Foundation

/// One Codable value in one JSON file. Good enough for modes and history; swap for SwiftData if it outgrows this.
public struct JSONStore<Value: Codable>: Sendable where Value: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    /// Default location: ~/Library/Application Support/Flow/<name>.json
    /// FLOW_STATE_DIR (dev/testing) redirects everything so a test run never touches real modes or history.
    public static func appSupport(_ name: String) -> JSONStore {
        let dir = ProcessInfo.processInfo.environment["FLOW_STATE_DIR"].map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Flow", directoryHint: .isDirectory)
        return JSONStore(url: dir.appending(path: "\(name).json"))
    }

    /// nil if the file is missing. An unreadable file is moved aside to `.corrupt` (never deleted) and treated as missing.
    public func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Value.self, from: data)
        } catch {
            let aside = url.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
            return nil
        }
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
