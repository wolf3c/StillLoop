import Foundation
import XCTest
@testable import StillLoop
import StillLoopCore

final class OpenAICompatibleLLMEngineTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocolStub.requestHandler = nil
    }

    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testCompletionRequestUsesRecommendedQwenSamplingSettings() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        var requestBody: [String: Any]?

        URLProtocolStub.requestHandler = { request in
            if request.url?.path == "/v1/chat/completions" {
                let data = try XCTUnwrap(request.bodyData)
                requestBody = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("""
                {"choices":[{"message":{"content":"{}"}}]}
                """.utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }

        let engine = OpenAICompatibleLLMEngine(
            baseURL: URL(string: "http://127.0.0.1:17631/v1")!,
            model: "qwen3.5-0.8b",
            session: session
        )

        _ = try await engine.complete(messages: [
            LLMMessage(role: .user, content: [.text("status")])
        ])

        XCTAssertEqual(requestBody?["temperature"] as? Double, 0.7)
        XCTAssertEqual(requestBody?["top_p"] as? Double, 0.8)
        XCTAssertEqual(requestBody?["top_k"] as? Int, 20)
        XCTAssertEqual(requestBody?["presence_penalty"] as? Double, 1.5)
        XCTAssertEqual(requestBody?["max_tokens"] as? Int, 500)
        XCTAssertEqual(requestBody?["stream"] as? Bool, false)
        XCTAssertNil(requestBody?["chat_template_kwargs"])
    }

    func testCompletionRequestCanDisableReasoningForBundledLlamaServer() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        var requestBody: [String: Any]?

        URLProtocolStub.requestHandler = { request in
            if request.url?.path == "/v1/chat/completions" {
                let data = try XCTUnwrap(request.bodyData)
                requestBody = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("""
                {"choices":[{"message":{"content":"{}"}}]}
                """.utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }

        let engine = OpenAICompatibleLLMEngine(
            baseURL: URL(string: "http://127.0.0.1:17631/v1")!,
            model: "Qwen3.5-0.8B-Base.Q4_K_M.gguf",
            disablesReasoning: true,
            session: session
        )

        _ = try await engine.complete(messages: [
            LLMMessage(role: .user, content: [.text("status")])
        ])

        let kwargs = try XCTUnwrap(requestBody?["chat_template_kwargs"] as? [String: Any])
        XCTAssertEqual(kwargs["enable_thinking"] as? Bool, false)
    }

    func testCompletionRequestCanConstrainFocusEvaluationToJSONSchema() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        var requestBody: [String: Any]?

        URLProtocolStub.requestHandler = { request in
            if request.url?.path == "/v1/chat/completions" {
                let data = try XCTUnwrap(request.bodyData)
                requestBody = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("""
                {"choices":[{"message":{"content":"{}"}}]}
                """.utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }

        let engine = OpenAICompatibleLLMEngine(
            baseURL: URL(string: "http://127.0.0.1:17631/v1")!,
            model: "Qwen3.5-0.8B-Base.Q4_K_M.gguf",
            usesResponseFormat: true,
            session: session
        )

        _ = try await engine.complete(
            messages: [
                LLMMessage(role: .user, content: [.text("status")])
            ],
            responseFormat: .focusEvaluation
        )

        let responseFormat = try XCTUnwrap(requestBody?["response_format"] as? [String: Any])
        XCTAssertEqual(responseFormat["type"] as? String, "json_schema")
        let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
        XCTAssertEqual(jsonSchema["name"] as? String, "focus_evaluation")
        XCTAssertEqual(jsonSchema["strict"] as? Bool, true)
        let schema = try XCTUnwrap(jsonSchema["schema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let state = try XCTUnwrap(properties["state"] as? [String: Any])
        XCTAssertEqual(state["enum"] as? [String], ["focused", "uncertain", "distracted", "stuck", "resting", "away"])
    }

    func testCompletionRequestIgnoresStructuredResponseFormatByDefault() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        var requestBody: [String: Any]?

        URLProtocolStub.requestHandler = { request in
            if request.url?.path == "/v1/chat/completions" {
                let data = try XCTUnwrap(request.bodyData)
                requestBody = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("""
                {"choices":[{"message":{"content":"{}"}}]}
                """.utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }

        let engine = OpenAICompatibleLLMEngine(
            baseURL: URL(string: "http://127.0.0.1:17631/v1")!,
            model: "manual-model",
            session: session
        )

        _ = try await engine.complete(
            messages: [
                LLMMessage(role: .user, content: [.text("status")])
            ],
            responseFormat: .focusEvaluation
        )

        XCTAssertNil(requestBody?["response_format"])
    }

    func testReadinessProbeRequiresImageInputWhenRequested() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        var chatRequestBodies: [[String: Any]] = []

        URLProtocolStub.requestHandler = { request in
            if request.url?.path == "/v1/models" {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("""
                {"data":[{"id":"qwen3.5-0.8b-heretic-ara-high-kld-v3-i1-iq4_nl"}]}
                """.utf8))
            }
            if request.url?.path == "/v1/chat/completions" {
                let data = try XCTUnwrap(request.bodyData)
                let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
                chatRequestBodies.append(body)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("""
                {"choices":[{"message":{"content":"OK"}}]}
                """.utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }

        let engine = OpenAICompatibleLLMEngine(
            baseURL: URL(string: "http://127.0.0.1:17631/v1")!,
            model: "qwen3.5-0.8b-heretic-ara-high-kld-v3-i1-iq4_nl",
            session: session
        )

        let result = try await engine.checkModelReadiness(requiresImageInput: true)

        XCTAssertTrue(result.chatCompletionWorks)
        XCTAssertEqual(result.visualCapability, .supported)
        XCTAssertEqual(chatRequestBodies.count, 2)
        let visualBody = try XCTUnwrap(chatRequestBodies.last)
        let messages = try XCTUnwrap(visualBody["messages"] as? [[String: Any]])
        let userMessage = try XCTUnwrap(messages.last)
        let content = try XCTUnwrap(userMessage["content"] as? [[String: Any]])
        XCTAssertTrue(content.contains { part in
            guard let imageURL = part["image_url"] as? [String: Any] else { return false }
            return part["type"] as? String == "image_url"
                && (imageURL["url"] as? String)?.hasPrefix("data:image/png;base64,") == true
        })
    }

    func testManualModelBaseURLStartsEmptyWithoutExplicitConfiguration() {
        let baseURL = AppModel.resolvedLLMBaseURLText(
            environmentValue: nil,
            storedValue: nil
        )

        XCTAssertEqual(baseURL, "")
    }

    func testLegacyDevelopmentBaseURLDefaultsAreNotShownAsUserConfiguration() {
        let baseURL = AppModel.resolvedLLMBaseURLText(
            environmentValue: nil,
            storedValue: "http://127.0.0.1:8080/v1"
        )

        XCTAssertEqual(baseURL, "")
        XCTAssertEqual(
            AppModel.resolvedLLMBaseURLText(
                environmentValue: nil,
                storedValue: "http://127.0.0.1:17631/v1"
            ),
            ""
        )
    }

    func testManualModelNameStartsEmptyWithoutExplicitConfiguration() {
        XCTAssertEqual(
            AppModel.resolvedLLMModelText(environmentValue: nil, storedValue: nil),
            ""
        )
        XCTAssertEqual(
            AppModel.resolvedLLMModelText(
                environmentValue: nil,
                storedValue: "qwen3.5-0.8b-heretic-ara-high-kld-v3-i1-iq4_nl"
            ),
            ""
        )
        XCTAssertEqual(
            AppModel.resolvedLLMModelText(
                environmentValue: nil,
                storedValue: ModelDownloadSpec.builtIn.localServerModelID
            ),
            ""
        )
    }

    func testCustomStoredBaseURLIsPreserved() {
        let baseURL = AppModel.resolvedLLMBaseURLText(
            environmentValue: nil,
            storedValue: "http://127.0.0.1:1234/v1"
        )

        XCTAssertEqual(baseURL, "http://127.0.0.1:1234/v1")
    }

    func testBareLocalHTTPBaseURLUsesOpenAICompatibleV1Path() {
        XCTAssertEqual(
            AppModel.effectiveLLMBaseURLText("http://127.0.0.1:8080"),
            "http://127.0.0.1:8080/v1"
        )
    }

    func testExistingBaseURLPathIsPreserved() {
        XCTAssertEqual(
            AppModel.effectiveLLMBaseURLText("http://127.0.0.1:8080/v1"),
            "http://127.0.0.1:8080/v1"
        )
        XCTAssertEqual(
            AppModel.effectiveLLMBaseURLText("http://127.0.0.1:8080/custom"),
            "http://127.0.0.1:8080/custom"
        )
    }

    func testLocalHTTPBaseURLRootTextHidesV1Path() {
        XCTAssertEqual(
            AppModel.localHTTPBaseURLRootText("http://127.0.0.1:8080/v1"),
            "http://127.0.0.1:8080"
        )
        XCTAssertEqual(
            AppModel.localHTTPBaseURLRootText("http://127.0.0.1:8080/custom"),
            "http://127.0.0.1:8080/custom"
        )
    }

    func testEnvironmentBaseURLOverridesStoredValue() {
        let baseURL = AppModel.resolvedLLMBaseURLText(
            environmentValue: "http://127.0.0.1:7777/v1",
            storedValue: "http://127.0.0.1:8080/v1"
        )

        XCTAssertEqual(baseURL, "http://127.0.0.1:7777/v1")
    }

    func testEnvironmentModelNameOverridesStoredValue() {
        XCTAssertEqual(
            AppModel.resolvedLLMModelText(environmentValue: "qwen-dev", storedValue: "custom-model"),
            "qwen-dev"
        )
    }

    @MainActor
    func testSelectingOnlineModelServiceDoesNotAutoFillProviderURL() {
        let model = AppModel()
        model.llmBaseURLText = ""

        model.selectManualModelService(.online)

        XCTAssertEqual(model.llmBaseURLText, "")
    }

    func testLocalLLMEnvironmentSelectsManualLocalModelSetup() {
        XCTAssertEqual(
            AppModel.resolvedModelSetupSelection(useLocalLLM: true),
            ModelSetupSelection(source: .manual, manualService: .localHTTP)
        )
        XCTAssertEqual(
            AppModel.resolvedModelSetupSelection(useLocalLLM: false),
            ModelSetupSelection(source: .bundled, manualService: .localHTTP)
        )
    }
}

private final class URLProtocolStub: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    var bodyData: Data? {
        if let httpBody {
            return httpBody
        }
        guard let httpBodyStream else {
            return nil
        }

        httpBodyStream.open()
        defer { httpBodyStream.close() }

        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while httpBodyStream.hasBytesAvailable {
            let read = httpBodyStream.read(buffer, maxLength: bufferSize)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}
