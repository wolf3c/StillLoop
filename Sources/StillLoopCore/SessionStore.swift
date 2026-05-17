import Foundation

public protocol SessionStore {
    func loadSummaries() throws -> [SessionSummary]
    func save(summary: SessionSummary) throws
}

public final class FileSessionStore: SessionStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public convenience init(appSupportDirectory: URL) {
        self.init(fileURL: appSupportDirectory.appendingPathComponent("session-summaries.json"))
    }

    public func loadSummaries() throws -> [SessionSummary] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([SessionSummary].self, from: data)
    }

    public func save(summary: SessionSummary) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var summaries = try loadSummaries()
        summaries.removeAll { $0.id == summary.id }
        summaries.insert(summary, at: 0)
        let data = try encoder.encode(summaries)
        try data.write(to: fileURL, options: .atomic)
    }

    public func update(summary: SessionSummary) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var summaries = try loadSummaries()
        if let index = summaries.firstIndex(where: { $0.id == summary.id }) {
            summaries[index] = summary
        } else {
            summaries.insert(summary, at: 0)
        }
        let data = try encoder.encode(summaries)
        try data.write(to: fileURL, options: .atomic)
    }
}
