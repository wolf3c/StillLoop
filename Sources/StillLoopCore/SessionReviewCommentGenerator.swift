import Foundation

public protocol SessionReviewCommentGenerating {
    func generateComment(for session: FocusSession) async throws -> String
}

public final class SessionReviewCommentGenerator: SessionReviewCommentGenerating {
    public enum GenerationError: Error, Equatable {
        case insufficientSessionContext
        case emptyComment
        case invalidCommentLanguage
    }

    private struct ModelResponse: Decodable {
        var comment: String
    }

    private let engine: LocalLLMEngine
    private let decoder = JSONDecoder()

    public init(engine: LocalLLMEngine) {
        self.engine = engine
    }

    public func generateComment(for session: FocusSession) async throws -> String {
        guard !session.events.isEmpty else {
            throw GenerationError.insufficientSessionContext
        }
        let response = try await engine.complete(messages: messages(for: session))
        let modelResponse = try LLMJSONResponseExtractor.decodeFirst(ModelResponse.self, from: response, using: decoder)
        let comment = normalizedComment(modelResponse.comment)
        guard !comment.isEmpty else {
            throw GenerationError.emptyComment
        }
        guard isValidChineseComment(comment) else {
            throw GenerationError.invalidCommentLanguage
        }
        return comment
    }

    private func messages(for session: FocusSession) -> [LLMMessage] {
        [
            LLMMessage(role: .system, content: [.text(systemPrompt)]),
            LLMMessage(role: .user, content: [.text(prompt(for: session))])
        ]
    }

    private var systemPrompt: String {
        """
        You are StillLoop, a local privacy-first focus companion.
        Write a short, positive Chinese review comment for the completed focus session.
        The comment must be specific to the provided session process, not generic praise.
        Use Simplified Chinese only. Keep app names and task text as-is if needed, but do not write Japanese or English prose.
        Use about 70-120 Chinese characters in 1-2 sentences.
        First acknowledge concrete effort or recovery from this session, then give one practical next-session suggestion.
        End naturally with continuing another focus session or keeping the rhythm. Do not mention the product name.
        Return only strict JSON:
        {"comment":"..."}
        """
    }

    private func prompt(for session: FocusSession) -> String {
        let summary = SessionSummary(session: session)
        return """
        Current task: \(session.task)
        Total duration: \(durationMinutes(summary.totalDuration)) minutes
        State counts: \(stateCountsLine(for: session.events))
        Nudge count: \(summary.nudgeCount)
        Top apps: \(topAppsLine(summary.topApps))
        Nudges used: \(nudgesLine(for: session.events))

        Recent timeline:
        \(timelineLine(for: session.events))
        """
    }

    private func durationMinutes(_ duration: TimeInterval) -> Int {
        max(0, Int((duration / 60).rounded(.down)))
    }

    private func stateCountsLine(for events: [FocusEvent]) -> String {
        FocusState.allCases
            .map { state in
                "\(state.rawValue)=\(events.filter { $0.state == state }.count)"
            }
            .joined(separator: ", ")
    }

    private func topAppsLine(_ topApps: [String: Int]) -> String {
        let parts = topApps
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
                }
                return lhs.value > rhs.value
            }
            .prefix(5)
            .map { "\($0.key)=\($0.value)" }
        return parts.isEmpty ? "none" : parts.joined(separator: ", ")
    }

    private func nudgesLine(for events: [FocusEvent]) -> String {
        let nudges = events
            .compactMap { $0.nudge?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(5)
        return nudges.isEmpty ? "none" : nudges.joined(separator: " | ")
    }

    private func timelineLine(for events: [FocusEvent]) -> String {
        let lines = events.prefix(8).map { event in
            "- \(event.state.rawValue): \(event.context)"
        }
        return lines.isEmpty ? "none" : lines.joined(separator: "\n")
    }

    private func normalizedComment(_ comment: String) -> String {
        comment
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isValidChineseComment(_ comment: String) -> Bool {
        let scalars = comment.unicodeScalars
        let hasCJK = scalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
                || (0x3400...0x4DBF).contains(Int(scalar.value))
                || (0xF900...0xFAFF).contains(Int(scalar.value))
        }
        let hasJapaneseKana = scalars.contains { scalar in
            (0x3040...0x309F).contains(Int(scalar.value))
                || (0x30A0...0x30FF).contains(Int(scalar.value))
                || (0xFF65...0xFF9F).contains(Int(scalar.value))
        }
        return hasCJK && !hasJapaneseKana
    }

}
