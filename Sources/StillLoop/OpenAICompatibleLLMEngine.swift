import Foundation
import StillLoopCore

final class OpenAICompatibleLLMEngine: StructuredLocalLLMEngine {
    enum VisualCapability: Equatable {
        case supported
        case notAdvertised
        case unknown
    }

    enum ReadinessError: Error {
        case imageInputUnavailable
    }

    struct ConnectionCheckResult: Equatable {
        var modelFound: Bool
        var chatCompletionWorks: Bool
        var visualCapability: VisualCapability
    }

    struct RequestBody: Encodable {
        struct ChatTemplateKwargs: Encodable {
            var enable_thinking: Bool
        }

        struct Message: Encodable {
            struct TextPart: Encodable {
                var type = "text"
                var text: String
            }

            struct ImagePart: Encodable {
                struct ImageURL: Encodable {
                    var url: String
                }

                var type = "image_url"
                var image_url: ImageURL
            }

            enum Content: Encodable {
                case text(String)
                case parts([LLMMessage.Content])

                func encode(to encoder: Encoder) throws {
                    switch self {
                    case .text(let text):
                        var container = encoder.singleValueContainer()
                        try container.encode(text)
                    case .parts(let parts):
                        var container = encoder.unkeyedContainer()
                        for part in parts {
                            switch part {
                            case .text(let text):
                                try container.encode(TextPart(text: text))
                            case .image(let mimeType, let data):
                                try container.encode(ImagePart(image_url: .init(url: "data:\(mimeType);base64,\(data.base64EncodedString())")))
                            }
                        }
                    }
                }
            }

            var role: String
            var content: Content
        }

        var model: String
        var messages: [Message]
        var temperature: Double
        var top_p: Double
        var top_k: Int
        var presence_penalty: Double
        var max_tokens: Int
        var stream: Bool
        var chat_template_kwargs: ChatTemplateKwargs?
        var response_format: FocusResponseFormat?
    }

    struct FocusResponseFormat: Encodable {
        struct Definition: Encodable {
            var name: String
            var strict: Bool
            var schema: ObjectSchema
        }

        struct ObjectSchema: Encodable {
            var type = "object"
            var additionalProperties = false
            var properties: Properties
            var required: [String]
        }

        struct Properties: Encodable {
            var analysis: AnalysisSchema?
            var state: StateSchema?
            var reason: StringSchema?
            var nudge: NullableStringSchema?
        }

        struct AnalysisProperties: Encodable {
            var userEngagement: StringSchema?
            var screenContent: StringSchema?
            var observedActivity: StringSchema?
            var taskAlignment: StringSchema?
            var decisionRationale: StringSchema?
            var userEngaged: BooleanSchema?
            var taskAligned: BooleanSchema?
        }

        struct AnalysisSchema: Encodable {
            var type = "object"
            var additionalProperties = false
            var properties = AnalysisProperties(
                userEngagement: .init(),
                screenContent: .init(),
                observedActivity: .init(),
                taskAlignment: .init(),
                decisionRationale: .init(),
                userEngaged: .init(),
                taskAligned: .init()
            )
            var required = [
                "userEngagement",
                "screenContent",
                "observedActivity",
                "taskAlignment",
                "decisionRationale",
                "userEngaged",
                "taskAligned"
            ]
        }

        struct StateSchema: Encodable {
            var type = "string"
            var `enum` = ["focused", "uncertain", "distracted", "stuck", "resting", "away"]
        }

        struct StringSchema: Encodable {
            var type = "string"
        }

        struct BooleanSchema: Encodable {
            var type = "boolean"
        }

        struct NullableStringSchema: Encodable {
            enum CodingKeys: String, CodingKey {
                case type
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(["string", "null"], forKey: .type)
            }
        }

        var type = "json_schema"
        var json_schema: Definition

        static let focusEvaluation = FocusResponseFormat(
            json_schema: Definition(
                name: "focus_evaluation",
                strict: true,
                schema: ObjectSchema(
                    properties: Properties(
                        analysis: .init(),
                        state: .init(),
                        reason: .init(),
                        nudge: .init()
                    ),
                    required: ["analysis", "state", "reason", "nudge"]
                )
            )
        )
    }

    struct ResponseBody: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                var content: String
            }

            var message: Message
        }

        var choices: [Choice]
    }

    private struct ModelsResponse: Decodable {
        struct ModelInfo: Decodable {
            var id: String
            var owned_by: String?
        }

        var data: [ModelInfo]
    }

    private let baseURL: URL
    private let model: String
    private let apiKey: String?
    private let session: URLSession
    private let disablesReasoning: Bool
    private let usesResponseFormat: Bool

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

    func complete(messages: [LLMMessage], responseFormat: LLMResponseFormat?) async throws -> String {
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthentication(to: &request)
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                model: model,
                messages: messages.map { message in
                    .init(role: message.role.rawValue, content: content(for: message.content))
                },
                temperature: 0.7,
                top_p: 0.8,
                top_k: 20,
                presence_penalty: 1.5,
                max_tokens: 900,
                stream: false,
                chat_template_kwargs: disablesReasoning
                    ? .init(enable_thinking: false)
                    : nil,
                response_format: usesResponseFormat
                    ? Self.openAIResponseFormat(for: responseFormat)
                    : nil
            )
        )

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let body = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let content = body.choices.first?.message.content else {
            throw URLError(.cannotParseResponse)
        }
        return content
    }

    private static func openAIResponseFormat(for responseFormat: LLMResponseFormat?) -> FocusResponseFormat? {
        switch responseFormat {
        case .focusEvaluation:
            return .focusEvaluation
        case nil:
            return nil
        }
    }

    private func content(for parts: [LLMMessage.Content]) -> RequestBody.Message.Content {
        if parts.count == 1, case .text(let text) = parts[0] {
            return .text(text)
        }
        return .parts(parts)
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
