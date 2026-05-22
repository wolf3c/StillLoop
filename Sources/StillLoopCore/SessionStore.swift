import Foundation

public protocol SessionStore {
    func loadSummaries() throws -> [SessionSummary]
    func save(summary: SessionSummary) throws
}

public final class FileSessionStore: SessionStore {
    private let summariesFileURL: URL
    private let sessionsFileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.summariesFileURL = fileURL
        self.sessionsFileURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("session-events.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public convenience init(appSupportDirectory: URL) {
        self.init(fileURL: appSupportDirectory.appendingPathComponent("session-summaries.json"))
    }

    public func loadSummaries() throws -> [SessionSummary] {
        guard FileManager.default.fileExists(atPath: summariesFileURL.path) else { return [] }
        let data = try Data(contentsOf: summariesFileURL)
        return try decoder.decode([SessionSummary].self, from: data)
    }

    public func save(summary: SessionSummary) throws {
        try FileManager.default.createDirectory(
            at: summariesFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var summaries = try loadSummaries()
        summaries.removeAll { $0.id == summary.id }
        summaries.insert(summary, at: 0)
        let data = try encoder.encode(summaries)
        try data.write(to: summariesFileURL, options: .atomic)
    }

    public func update(summary: SessionSummary) throws {
        try FileManager.default.createDirectory(
            at: summariesFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var summaries = try loadSummaries()
        if let index = summaries.firstIndex(where: { $0.id == summary.id }) {
            summaries[index] = summary
        } else {
            summaries.insert(summary, at: 0)
        }
        let data = try encoder.encode(summaries)
        try data.write(to: summariesFileURL, options: .atomic)
    }

    public func removeSummary(id: UUID) throws {
        try FileManager.default.createDirectory(
            at: summariesFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var summaries = try loadSummaries()
        summaries.removeAll { $0.id == id }
        let data = try encoder.encode(summaries)
        try data.write(to: summariesFileURL, options: .atomic)
    }

    public func loadSessions() throws -> [FocusSession] {
        guard FileManager.default.fileExists(atPath: sessionsFileURL.path) else { return [] }
        let data = try Data(contentsOf: sessionsFileURL)
        return try decoder.decode([FocusSession].self, from: data)
    }

    public func save(session: FocusSession) throws {
        try FileManager.default.createDirectory(
            at: sessionsFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var sessions = try loadSessions()
        sessions.removeAll { $0.id == session.id }
        sessions.insert(session, at: 0)
        let data = try encoder.encode(sessions)
        try data.write(to: sessionsFileURL, options: .atomic)
    }

    public func update(session: FocusSession) throws {
        try FileManager.default.createDirectory(
            at: sessionsFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var sessions = try loadSessions()
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        let data = try encoder.encode(sessions)
        try data.write(to: sessionsFileURL, options: .atomic)
    }
}
