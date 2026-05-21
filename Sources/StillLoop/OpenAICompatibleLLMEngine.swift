import Foundation
import StillLoopCore

final class OpenAICompatibleLLMEngine: StructuredLocalLLMEngine, LLMRequestTransportMetricsProviding, LLMInputTextTokenCounting, LLMFocusPromptCachePrewarming, LLMFocusPromptCacheProbing {
    private static let defaultMaxTokens = 900
    private static let focusEvaluationMaxTokens = 420

    enum VisualCapability: Equatable {
        case supported
        case notAdvertised
        case unknown
    }

    private enum OrderedJSONValue {
        case object([(String, OrderedJSONValue)])
        case array([OrderedJSONValue])
        case string(String)
        case number(String)
        case bool(Bool)
        case null

        func encodedData() throws -> Data {
            Data(try encodedString().utf8)
        }

        private func encodedString() throws -> String {
            switch self {
            case .object(let fields):
                let body = try fields
                    .map { key, value in
                        try "\(Self.escapedString(key)):\(value.encodedString())"
                    }
                    .joined(separator: ",")
                return "{\(body)}"
            case .array(let values):
                let body = try values
                    .map { try $0.encodedString() }
                    .joined(separator: ",")
                return "[\(body)]"
            case .string(let value):
                return try Self.escapedString(value)
            case .number(let value):
                return value
            case .bool(let value):
                return value ? "true" : "false"
            case .null:
                return "null"
            }
        }

        private static func escapedString(_ value: String) throws -> String {
            let data = try JSONEncoder().encode(value)
            return String(decoding: data, as: UTF8.self)
        }
    }

    enum ReadinessError: Error {
        case imageInputUnavailable
    }

    struct ConnectionCheckResult: Equatable {
        var modelFound: Bool
        var chatCompletionWorks: Bool
        var visualCapability: VisualCapability
    }

    struct ResponseBody: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                var content: String
            }

            var message: Message
        }

        var choices: [Choice]
        var created: Int?
        var usage: LLMUsageValue?
        var timings: LLMUsageValue?
    }

    private struct ModelsResponse: Decodable {
        struct ModelInfo: Decodable {
            var id: String
            var owned_by: String?
        }

        var data: [ModelInfo]
    }

    private struct TokenizeRequest: Encodable {
        var content: String
        var add_special = false
        var parse_special = true
        var with_pieces = false
    }

    private struct TokenizeResponse: Decodable {
        var tokens: [Int]
    }

    private let baseURL: URL
    private let model: String
    private let apiKey: String?
    private let session: URLSession
    private let disablesReasoning: Bool
    private let usesResponseFormat: Bool
    private(set) var lastRequestTransportMetrics: LLMRequestTransportMetrics?

    init(
        baseURL: URL,
        model: String,
        apiKey: String? = nil,
        disablesReasoning: Bool = false,
        usesResponseFormat: Bool = false,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.session = session
        self.disablesReasoning = disablesReasoning
        self.usesResponseFormat = usesResponseFormat
    }

    func checkConnection() async throws {
        _ = try await checkModelReadiness()
    }

    func checkModelReadiness(requiresImageInput: Bool = false) async throws -> ConnectionCheckResult {
        let models = try await fetchModels()
        let normalizedTarget = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let selectedModel = models.first(where: { $0.id.lowercased() == normalizedTarget }) else {
            throw URLError(.cannotFindHost)
        }

        _ = try await complete(messages: [
            .init(role: .system, content: [.text("Reply with OK only.")]),
            .init(role: .user, content: [.text("OK")])
        ])
        if requiresImageInput {
            do {
                _ = try await complete(messages: [
                    .init(role: .system, content: [.text("Reply with OK only.")]),
                    .init(role: .user, content: [
                        .text("Confirm that you can read this image input. Reply with OK only."),
                        .image(mimeType: "image/png", data: Self.readinessProbePNG)
                    ])
                ])
            } catch {
                throw ReadinessError.imageInputUnavailable
            }
        }
        return ConnectionCheckResult(
            modelFound: true,
            chatCompletionWorks: true,
            visualCapability: requiresImageInput ? .supported : visualCapability(for: selectedModel.id)
        )
    }

    private func fetchModels() async throws -> [ModelsResponse.ModelInfo] {
        let endpoint = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 6
        applyAuthentication(to: &request)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ModelsResponse.self, from: data).data
    }

    private func visualCapability(for modelID: String) -> VisualCapability {
        let id = modelID.lowercased()
        if id.contains("vl") || id.contains("vision") || id.contains("visual") || id.contains("llava") {
            return .supported
        }
        if id.contains("qwen") || id.contains("llama") || id.contains("mistral") {
            return .notAdvertised
        }
        return .unknown
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        try await complete(messages: messages, responseFormat: nil)
    }

    func prewarmFocusEvaluationPrompt(
        messages: [LLMMessage],
        responseFormat: LLMResponseFormat?
    ) async throws {
        _ = try await sendChatCompletion(
            messages: messages,
            responseFormat: responseFormat,
            maxTokens: 1
        )
    }

    func runFocusPromptCacheProbe(
        messages: [LLMMessage],
        responseFormat: LLMResponseFormat?
    ) async throws -> LLMRequestTransportMetrics {
        let result = try await sendChatCompletion(
            messages: messages,
            responseFormat: responseFormat,
            maxTokens: 1
        )
        let body = try JSONDecoder().decode(ResponseBody.self, from: result.data)
        guard let content = body.choices.first?.message.content else {
            throw URLError(.cannotParseResponse)
        }
        return LLMRequestTransportMetrics(
            payloadBytes: result.payloadBytes,
            responseChars: content.count,
            inputTextTokenCount: nil,
            created: body.created,
            usage: body.usage,
            timings: body.timings
        )
    }

    func complete(messages: [LLMMessage], responseFormat: LLMResponseFormat?) async throws -> String {
        lastRequestTransportMetrics = nil
        let result = try await sendChatCompletion(
            messages: messages,
            responseFormat: responseFormat,
            maxTokens: responseFormat == .focusEvaluation ? Self.focusEvaluationMaxTokens : Self.defaultMaxTokens
        )
        let body = try JSONDecoder().decode(ResponseBody.self, from: result.data)
        guard let content = body.choices.first?.message.content else {
            throw URLError(.cannotParseResponse)
        }
        lastRequestTransportMetrics = LLMRequestTransportMetrics(
            payloadBytes: result.payloadBytes,
            responseChars: content.count,
            inputTextTokenCount: nil,
            created: body.created,
            usage: body.usage,
            timings: body.timings
        )
        return content
    }

    private func sendChatCompletion(
        messages: [LLMMessage],
        responseFormat: LLMResponseFormat?,
        maxTokens: Int
    ) async throws -> (data: Data, payloadBytes: Int) {
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthentication(to: &request)
        let payload = try chatCompletionPayload(
            messages: messages,
            responseFormat: responseFormat,
            maxTokens: maxTokens
        )
        request.httpBody = payload

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return (data, payload.count)
    }

    private func chatCompletionPayload(
        messages: [LLMMessage],
        responseFormat: LLMResponseFormat?,
        maxTokens: Int
    ) throws -> Data {
        var fields: [(String, OrderedJSONValue)] = [
            ("model", .string(model)),
            ("messages", .array(messages.map(jsonMessage(for:)))),
            ("temperature", .number("0.7")),
            ("top_p", .number("0.8")),
            ("top_k", .number("20")),
            ("presence_penalty", .number("1.5")),
            ("max_tokens", .number("\(maxTokens)")),
            ("stream", .bool(false))
        ]
        if disablesReasoning {
            fields.append(("chat_template_kwargs", .object([
                ("enable_thinking", .bool(false))
            ])))
        }
        if usesResponseFormat, responseFormat == .focusEvaluation {
            fields.append(("response_format", Self.focusEvaluationResponseFormatJSON()))
        }
        return try OrderedJSONValue.object(fields).encodedData()
    }

    private func jsonMessage(for message: LLMMessage) -> OrderedJSONValue {
        .object([
            ("role", .string(message.role.rawValue)),
            ("content", jsonContent(for: message.content))
        ])
    }

    private func jsonContent(for parts: [LLMMessage.Content]) -> OrderedJSONValue {
        if parts.count == 1, case .text(let text) = parts[0] {
            return .string(text)
        }
        return .array(parts.map { part in
            switch part {
            case .text(let text):
                return .object([
                    ("type", .string("text")),
                    ("text", .string(text))
                ])
            case .image(let mimeType, let data):
                return .object([
                    ("type", .string("image_url")),
                    ("image_url", .object([
                        ("url", .string("data:\(mimeType);base64,\(data.base64EncodedString())"))
                    ]))
                ])
            }
        })
    }

    private static func focusEvaluationResponseFormatJSON() -> OrderedJSONValue {
        .object([
            ("type", .string("json_schema")),
            ("json_schema", .object([
                ("name", .string("focus_evaluation")),
                ("strict", .bool(true)),
                ("schema", .object([
                    ("type", .string("object")),
                    ("additionalProperties", .bool(false)),
                    ("properties", .object([
                        ("analysis", .object([
                            ("type", .string("object")),
                            ("additionalProperties", .bool(false)),
                            ("properties", .object([
                                ("userEngagement", .object([("type", .string("string"))])),
                                ("userEngaged", .object([("type", .string("boolean"))])),
                                ("screenContent", .object([("type", .string("string"))])),
                                ("observedActivity", .object([("type", .string("string"))])),
                                ("taskAlignment", .object([("type", .string("string"))])),
                                ("taskAligned", .object([("type", .string("boolean"))]))
                            ])),
                            ("required", .array([
                                .string("userEngagement"),
                                .string("userEngaged"),
                                .string("screenContent"),
                                .string("observedActivity"),
                                .string("taskAlignment"),
                                .string("taskAligned")
                            ]))
                        ])),
                        ("reason", .object([("type", .string("string"))])),
                        ("state", .object([
                            ("type", .string("string")),
                            ("enum", .array([
                                .string("focused"),
                                .string("uncertain"),
                                .string("distracted"),
                                .string("stuck"),
                                .string("resting"),
                                .string("away")
                            ]))
                        ])),
                        ("focusTarget", .object([
                            ("type", .array([.string("object"), .string("null")])),
                            ("additionalProperties", .bool(false)),
                            ("properties", .object([
                                ("appName", .object([("type", .string("string"))])),
                                ("windowTitle", .object([("type", .array([.string("string"), .string("null")]))])),
                                ("browserTitle", .object([("type", .array([.string("string"), .string("null")]))])),
                                ("browserURL", .object([("type", .array([.string("string"), .string("null")]))]))
                            ])),
                            ("required", .array([
                                .string("appName"),
                                .string("windowTitle"),
                                .string("browserTitle"),
                                .string("browserURL")
                            ]))
                        ])),
                        ("nudge", .object([("type", .array([.string("string"), .string("null")]))]))
                    ])),
                    ("required", .array([
                        .string("analysis"),
                        .string("reason"),
                        .string("state"),
                        .string("focusTarget"),
                        .string("nudge")
                    ]))
                ]))
            ]))
        ])
    }

    func inputTextTokenCount(for text: String) async -> Int? {
        guard !text.isEmpty, isLocalBaseURL else {
            return nil
        }

        do {
            var request = URLRequest(url: tokenizeEndpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 2
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(TokenizeRequest(content: text))
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try JSONDecoder().decode(TokenizeResponse.self, from: data).tokens.count
        } catch {
            return nil
        }
    }

    private var isLocalBaseURL: Bool {
        guard let host = baseURL.host?.lowercased() else {
            return false
        }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private var tokenizeEndpoint: URL {
        guard baseURL.lastPathComponent == "v1" else {
            return baseURL.appendingPathComponent("tokenize")
        }
        return baseURL
            .deletingLastPathComponent()
            .appendingPathComponent("tokenize")
    }

    private func applyAuthentication(to request: inout URLRequest) {
        guard let apiKey else { return }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    private static let readinessProbePNG = Data(base64Encoded: """
    iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=
    """)!
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
