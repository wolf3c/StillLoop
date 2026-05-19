import Foundation

enum LLMJSONResponseExtractor {
    enum ExtractionError: Error {
        case noDecodableObject
    }

    static func decodeFirst<T: Decodable>(
        _ type: T.Type,
        from text: String,
        using decoder: JSONDecoder
    ) throws -> T {
        var seenCandidates = Set<String>()
        let sources = [textWithoutReasoningSections(text), text]
        for source in sources {
            for candidate in jsonObjectCandidates(in: source) where seenCandidates.insert(candidate).inserted {
                if let response = try? decoder.decode(type, from: Data(candidate.utf8)) {
                    return response
                }
            }
        }
        throw ExtractionError.noDecodableObject
    }

    private static func textWithoutReasoningSections(_ text: String) -> String {
        var output = text
        for tag in ["think", "thinking", "thought", "thoughts", "reason", "reasoning"] {
            output = removingTaggedSection(tag, from: output)
        }
        return trimmingLeadingReasoningBeforeFinalAnswer(in: output)
    }

    private static func removingTaggedSection(_ tag: String, from text: String) -> String {
        var output = text
        while true {
            guard
                let start = output.range(of: "<\(tag)", options: [.caseInsensitive]),
                let startTagEnd = output[start.upperBound...].firstIndex(of: ">"),
                let end = output.range(of: "</\(tag)>", options: [.caseInsensitive], range: startTagEnd..<output.endIndex)
            else {
                return output
            }
            output.removeSubrange(start.lowerBound..<end.upperBound)
        }
    }

    private static func trimmingLeadingReasoningBeforeFinalAnswer(in text: String) -> String {
        let reasoningMarkers = ["思考", "推理", "thought", "reason", "reasoning", "analysis"]
        let finalMarkers = ["最终答案", "最终输出", "最终判断", "final answer", "final output"]
        guard reasoningMarkers.contains(where: { text.range(of: $0, options: [.caseInsensitive]) != nil }) else {
            return text
        }
        let markerRanges = finalMarkers.compactMap { marker in
            text.range(of: marker, options: [.caseInsensitive]).map { range in
                (lower: range.lowerBound, upper: range.upperBound)
            }
        }
        guard let markerRange = markerRanges.min(by: { $0.lower < $1.lower }) else {
            return text
        }
        return String(text[markerRange.upper...])
    }

    private static func jsonObjectCandidates(in text: String) -> [String] {
        var candidates: [String] = []
        var objectStart: String.Index?
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            defer { index = text.index(after: index) }

            guard let start = objectStart else {
                if character == "{" {
                    objectStart = index
                    depth = 1
                    isInsideString = false
                    isEscaped = false
                }
                continue
            }

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            switch character {
            case "\"":
                isInsideString = true
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    candidates.append(String(text[start...index]))
                    objectStart = nil
                }
            default:
                break
            }
        }
        return candidates
    }
}
