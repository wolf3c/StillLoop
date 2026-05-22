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
        var requestTimeout: TimeInterval?

        URLProtocolStub.requestHandler = { request in
            if request.url?.path == "/v1/chat/completions" {
                requestTimeout = request.timeoutInterval
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
        XCTAssertEqual(requestBody?["max_tokens"] as? Int, 900)
        XCTAssertEqual(requestBody?["stream"] as? Bool, false)
        XCTAssertNil(requestBody?["chat_template_kwargs"])
        XCTAssertEqual(requestTimeout, 180)
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
        var requestBodyText = ""

        URLProtocolStub.requestHandler = { request in
            if request.url?.path == "/v1/chat/completions" {
                let data = try XCTUnwrap(request.bodyData)
                requestBodyText = String(decoding: data, as: UTF8.self)
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
        XCTAssertEqual(requestBody?["max_tokens"] as? Int, 420)
        XCTAssertEqual(responseFormat["type"] as? String, "json_schema")
        let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
        XCTAssertEqual(jsonSchema["name"] as? String, "focus_evaluation")
        XCTAssertEqual(jsonSchema["strict"] as? Bool, true)
        let schema = try XCTUnwrap(jsonSchema["schema"] as? [String: Any])
        XCTAssertLessThan(
            try XCTUnwrap(requestBodyText.range(of: #""analysis":{"#)?.lowerBound),
            try XCTUnwrap(requestBodyText.range(of: #""reason":{"#)?.lowerBound)
        )
        XCTAssertLessThan(
            try XCTUnwrap(requestBodyText.range(of: #""reason":{"#)?.lowerBound),
            try XCTUnwrap(requestBodyText.range(of: #""state":{"#)?.lowerBound)
        )
        XCTAssertLessThan(
            try XCTUnwrap(requestBodyText.range(of: #""state":{"#)?.lowerBound),
            try XCTUnwrap(requestBodyText.range(of: #""focusTargetID":{"#)?.lowerBound)
        )
        XCTAssertLessThan(
            try XCTUnwrap(requestBodyText.range(of: #""focusTargetID":{"#)?.lowerBound),
            try XCTUnwrap(requestBodyText.range(of: #""nudge":{"#)?.lowerBound)
        )
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let analysis = try XCTUnwrap(properties["analysis"] as? [String: Any])
        let analysisProperties = try XCTUnwrap(analysis["properties"] as? [String: Any])
        XCTAssertLessThan(
            try XCTUnwrap(requestBodyText.range(of: #""userEngagement":{"#)?.lowerBound),
            try XCTUnwrap(requestBodyText.range(of: #""userEngaged":{"#)?.lowerBound)
        )
        XCTAssertLessThan(
            try XCTUnwrap(requestBodyText.range(of: #""userEngaged":{"#)?.lowerBound),
            try XCTUnwrap(requestBodyText.range(of: #""screenContent":{"#)?.lowerBound)
        )
        let userEngaged = try XCTUnwrap(analysisProperties["userEngaged"] as? [String: Any])
        let taskAligned = try XCTUnwrap(analysisProperties["taskAligned"] as? [String: Any])
        XCTAssertEqual(userEngaged["type"] as? String, "boolean")
        XCTAssertEqual(taskAligned["type"] as? String, "boolean")
        XCTAssertEqual(
            analysis["required"] as? [String],
            ["userEngagement", "userEngaged", "screenContent", "observedActivity", "taskAlignment", "taskAligned"]
        )
        XCTAssertNil(analysisProperties["decisionRationale"])
        let state = try XCTUnwrap(properties["state"] as? [String: Any])
        XCTAssertEqual(state["enum"] as? [String], ["focused", "uncertain", "distracted", "stuck", "resting", "away"])
        let focusTargetID = try XCTUnwrap(properties["focusTargetID"] as? [String: Any])
        XCTAssertEqual(focusTargetID["type"] as? [String], ["string", "null"])
        XCTAssertNil(properties["focusTarget"])
        XCTAssertNil(properties["confidence"])
        XCTAssertEqual(schema["required"] as? [String], ["analysis", "reason", "state", "focusTargetID", "nudge"])
        XCTAssertFalse((schema["required"] as? [String])?.contains("confidence") == true)
    }

    func testPrewarmFocusEvaluationPromptUsesSingleTokenStructuredRequest() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        var requestBody: [String: Any]?

        URLProtocolStub.requestHandler = { request in
            if request.url?.path == "/v1/chat/completions" {
                let data = try XCTUnwrap(request.bodyData)
                requestBody = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("""
                {"choices":[{"message":{"content":"{"}}]}
                """.utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }

        let engine = OpenAICompatibleLLMEngine(
            baseURL: URL(string: "http://127.0.0.1:17631/v1")!,
            model: "Qwen3.5-0.8B-Base.Q4_K_M.gguf",
            disablesReasoning: true,
            usesResponseFormat: true,
            session: session
        )

        try await engine.prewarmFocusEvaluationPrompt(
            messages: [
                LLMMessage(role: .system, content: [.text("Stable system prompt")]),
                LLMMessage(role: .user, content: [.text("Warm up the focus evaluator.")])
            ],
            responseFormat: .focusEvaluation
        )

        XCTAssertEqual(requestBody?["max_tokens"] as? Int, 1)
        XCTAssertEqual(requestBody?["stream"] as? Bool, false)
        let kwargs = try XCTUnwrap(requestBody?["chat_template_kwargs"] as? [String: Any])
        XCTAssertEqual(kwargs["enable_thinking"] as? Bool, false)
        let responseFormat = try XCTUnwrap(requestBody?["response_format"] as? [String: Any])
        XCTAssertEqual(responseFormat["type"] as? String, "json_schema")
        let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
        XCTAssertEqual(jsonSchema["name"] as? String, "focus_evaluation")
        let messages = try XCTUnwrap(requestBody?["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        XCTAssertEqual(messages.last?["role"] as? String, "user")
        XCTAssertNil(engine.lastRequestTransportMetrics)
    }

    func testPromptCacheProbeUsesSingleTokenStructuredRequestAndReturnsMetrics() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        var requestPath: String?
        var requestBody: [String: Any]?
        var payloadBytes: Int?

        URLProtocolStub.requestHandler = { request in
            if request.url?.path == "/v1/chat/completions" {
                requestPath = request.url?.path
                let data = try XCTUnwrap(request.bodyData)
                payloadBytes = data.count
                requestBody = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("""
                {"choices":[{"message":{"content":"{"}}],"created":1779348997,"usage":{"completion_tokens":1,"prompt_tokens":3699,"prompt_tokens_details":{"cached_tokens":221},"total_tokens":3700},"timings":{"cache_n":221,"prompt_n":3478,"prompt_ms":5877.439,"predicted_n":1,"predicted_ms":20.5}}
                """.utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }

        let engine = OpenAICompatibleLLMEngine(
            baseURL: URL(string: "http://127.0.0.1:17631/v1")!,
            model: "Qwen3.5-0.8B-Base.Q4_K_M.gguf",
            disablesReasoning: true,
            usesResponseFormat: true,
            session: session
        )

        let metrics = try await engine.runFocusPromptCacheProbe(
            messages: [
                LLMMessage(role: .system, content: [.text("Stable system prompt")]),
                LLMMessage(role: .user, content: [.text("Warm up the focus evaluator.")])
            ],
            responseFormat: .focusEvaluation
        )

        XCTAssertEqual(requestPath, "/v1/chat/completions")
        XCTAssertEqual(requestBody?["max_tokens"] as? Int, 1)
        XCTAssertEqual(requestBody?["stream"] as? Bool, false)
        let kwargs = try XCTUnwrap(requestBody?["chat_template_kwargs"] as? [String: Any])
        XCTAssertEqual(kwargs["enable_thinking"] as? Bool, false)
        let responseFormat = try XCTUnwrap(requestBody?["response_format"] as? [String: Any])
        XCTAssertEqual(responseFormat["type"] as? String, "json_schema")
        let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
        XCTAssertEqual(jsonSchema["name"] as? String, "focus_evaluation")
        XCTAssertEqual(metrics.payloadBytes, payloadBytes)
        XCTAssertEqual(metrics.responseChars, 1)
        XCTAssertEqual(metrics.created, 1_779_348_997)
        XCTAssertEqual(
            metrics.usage?.compactJSONString,
            #"{"completion_tokens":1,"prompt_tokens":3699,"prompt_tokens_details":{"cached_tokens":221},"total_tokens":3700}"#
        )
        XCTAssertEqual(
            metrics.timings?.compactJSONString,
            #"{"cache_n":221,"predicted_ms":20.5,"predicted_n":1,"prompt_ms":5877.439,"prompt_n":3478}"#
        )
        XCTAssertNil(engine.lastRequestTransportMetrics)
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

    func testCompletionRecordsActualPayloadAndResponseDebugMetrics() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        var capturedPayloadBytes: Int?

        URLProtocolStub.requestHandler = { request in
            if request.url?.path == "/v1/chat/completions" {
                let data = try XCTUnwrap(request.bodyData)
                capturedPayloadBytes = data.count
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("""
                {"choices":[{"message":{"content":"focused"}}]}
                """.utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }

        let engine = OpenAICompatibleLLMEngine(
            baseURL: URL(string: "http://127.0.0.1:17631/v1")!,
            model: "manual-model",
            session: session
        )

        let response = try await engine.complete(messages: [
            LLMMessage(role: .user, content: [.text("status")])
        ])

        let metrics = try XCTUnwrap(engine.lastRequestTransportMetrics)
        XCTAssertEqual(metrics.payloadBytes, capturedPayloadBytes)
        XCTAssertEqual(metrics.responseChars, response.count)
        XCTAssertNil(metrics.inputTextTokenCount)
        XCTAssertNil(metrics.usage)
    }

    func testCompletionRecordsFullUsageAndTimingDebugMetrics() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)

        URLProtocolStub.requestHandler = { request in
            if request.url?.path == "/v1/chat/completions" {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("""
                {"choices":[{"message":{"content":"focused"}}],"created":1779341711,"usage":{"completion_tokens":8,"prompt_tokens":21,"total_tokens":29,"prompt_tokens_details":{"cached_tokens":0}},"timings":{"prompt_n":15,"prompt_ms":521.25,"predicted_n":8,"predicted_ms":1188.5}}
                """.utf8))
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }

        let engine = OpenAICompatibleLLMEngine(
            baseURL: URL(string: "http://127.0.0.1:17631/v1")!,
            model: "manual-model",
            session: session
        )

        _ = try await engine.complete(messages: [
            LLMMessage(role: .user, content: [.text("status")])
        ])

        let metrics = try XCTUnwrap(engine.lastRequestTransportMetrics)
        XCTAssertEqual(metrics.created, 1_779_341_711)
        XCTAssertEqual(
            metrics.usage?.compactJSONString,
            #"{"completion_tokens":8,"prompt_tokens":21,"prompt_tokens_details":{"cached_tokens":0},"total_tokens":29}"#
        )
        XCTAssertEqual(
            metrics.timings?.compactJSONString,
            #"{"predicted_ms":1188.5,"predicted_n":8,"prompt_ms":521.25,"prompt_n":15}"#
        )
    }

    func testLocalLlamaInputTextTokenCountUsesTokenizeEndpoint() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        var tokenizeBody: [String: Any]?

        URLProtocolStub.requestHandler = { request in
            if request.url?.path == "/tokenize" {
                let data = try XCTUnwrap(request.bodyData)
                tokenizeBody = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("""
                {"tokens":[101,102,103]}
                """.utf8))
            }
            if request.url?.path == "/v1/chat/completions" {
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

        let tokenCount = await engine.inputTextTokenCount(for: "system\nstatus")

        XCTAssertEqual(tokenizeBody?["content"] as? String, "system\nstatus")
        XCTAssertEqual(tokenCount, 3)
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
