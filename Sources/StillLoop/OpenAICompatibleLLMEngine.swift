import Foundation
import StillLoopCore

final class OpenAICompatibleLLMEngine: LocalLLMEngine {
    enum VisualCapability: Equatable {
        case supported
        case notAdvertised
        case unknown
    }

    struct ConnectionCheckResult: Equatable {
        var modelFound: Bool
        var chatCompletionWorks: Bool
        var visualCapability: VisualCapability
    }

    struct RequestBody: Encodable {
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
        var max_tokens: Int
        var stream: Bool
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
    private let session: URLSession

    init(baseURL: URL, model: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.model = model
        self.session = session
    }

    func checkConnection() async throws {
        _ = try await checkModelReadiness()
    }

    func checkModelReadiness() async throws -> ConnectionCheckResult {
        let models = try await fetchModels()
        let normalizedTarget = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let selectedModel = models.first(where: { $0.id.lowercased() == normalizedTarget }) else {
            throw URLError(.cannotFindHost)
        }

        _ = try await complete(messages: [
            .init(role: .system, content: [.text("Reply with OK only.")]),
            .init(role: .user, content: [.text("OK")])
        ])
        return ConnectionCheckResult(
            modelFound: true,
            chatCompletionWorks: true,
            visualCapability: visualCapability(for: selectedModel.id)
        )
    }

    private func fetchModels() async throws -> [ModelsResponse.ModelInfo] {
        let endpoint = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 6
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
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                model: model,
                messages: messages.map { message in
                    .init(role: message.role.rawValue, content: content(for: message.content))
                },
                temperature: 0.1,
                max_tokens: 500,
                stream: false
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

    private func content(for parts: [LLMMessage.Content]) -> RequestBody.Message.Content {
        if parts.count == 1, case .text(let text) = parts[0] {
            return .text(text)
        }
        return .parts(parts)
    }
}
