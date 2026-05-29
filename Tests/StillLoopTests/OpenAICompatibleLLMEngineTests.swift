import Darwin
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

    func testUnixSocketBaseURLSendsCompletionThroughUnixSocket() async throws {
        let socketURL = URL(fileURLWithPath: "/tmp/sl-\(UUID().uuidString.prefix(8)).sock")
        let server = try OneShotUnixSocketHTTPServer(
            socketURL: socketURL,
            responseBody: Data(#"{"choices":[{"message":{"content":"socket-ok"}}]}"#.utf8)
        )
        try server.start()
        defer { server.stop() }

        let engine = OpenAICompatibleLLMEngine(
            baseURL: OpenAICompatibleLLMEngine.unixSocketBaseURL(socketURL: socketURL),
            model: "manual-model"
        )

        let response = try await engine.complete(messages: [
            LLMMessage(role: .user, content: [.text("status")])
        ])

        let requestText = try server.capturedRequestText()
        XCTAssertEqual(response, "socket-ok")
        XCTAssertTrue(requestText.hasPrefix("POST /v1/chat/completions HTTP/1.1"))
        XCTAssertTrue(requestText.contains("Host: localhost"))
        XCTAssertTrue(requestText.contains(#""model":"manual-model""#))
    }

    func testUnixSocketTransportHonorsRequestTimeoutWhenServerDoesNotReply() async throws {
        let socketURL = URL(fileURLWithPath: "/tmp/sl-\(UUID().uuidString.prefix(8)).sock")
        let server = try OneShotUnixSocketHTTPServer(socketURL: socketURL, responseBody: nil)
        try server.start()
        defer { server.stop() }

        var request = URLRequest(url: URL(string: "http://localhost/v1/models")!)
        request.timeoutInterval = 0.05
        let transport = UnixSocketOpenAICompatibleHTTPTransport(socketURL: socketURL)
        let startedAt = Date()

        do {
            _ = try await transport.data(for: request)
            XCTFail("Expected Unix socket request to time out")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
            XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1)
        }
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
        XCTAssertEqual(requestBody?["min_p"] as? Double, 0.0)
        XCTAssertEqual(requestBody?["presence_penalty"] as? Double, 1.5)
        XCTAssertEqual(requestBody?["repeat_penalty"] as? Double, 1.0)
        XCTAssertEqual(requestBody?["max_tokens"] as? Int, 900)
        XCTAssertEqual(requestBody?["stream"] as? Bool, false)
        XCTAssertNil(requestBody?["id_slot"])
        XCTAssertNil(requestBody?["cache_prompt"])
        XCTAssertNil(requestBody?["chat_template_kwargs"])
        XCTAssertEqual(requestTimeout, 180)
    }

    func testCompletionRequestCanPinBundledLlamaServerSlot() async throws {
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
            llamaServerRequestOptions: .init(slotID: 2),
            session: session
        )

        _ = try await engine.complete(
            messages: [
                LLMMessage(role: .user, content: [.text("status")])
            ],
            responseFormat: .taskProgressEvaluation
        )

        XCTAssertEqual(requestBody?["id_slot"] as? Int, 2)
        XCTAssertEqual(requestBody?["cache_prompt"] as? Bool, true)
        XCTAssertEqual(engine.lastRequestTransportMetrics?.llamaServerSlotID, 2)
    }

    func testCompletionHTTPErrorExposesStatusAndResponseByteCountWithoutBody() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let body = Data(#"{"error":"slot unavailable"}"#.utf8)

        URLProtocolStub.requestHandler = { request in
            if request.url?.path == "/v1/chat/completions" {
                return (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, body)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }

        let engine = OpenAICompatibleLLMEngine(
            baseURL: URL(string: "http://127.0.0.1:17631/v1")!,
            model: "qwen3.5-0.8b",
            session: session
        )

        do {
            _ = try await engine.complete(messages: [
                LLMMessage(role: .user, content: [.text("status")])
            ])
            XCTFail("Expected HTTP status error")
        } catch let error as OpenAICompatibleLLMEngine.HTTPStatusError {
            XCTAssertEqual(error.statusCode, 503)
            XCTAssertEqual(error.responseByteCount, body.count)
        }
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

    func testCompletionRequestCanConstrainSplitEvaluationToJSONSchemas() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        var requestBodies: [[String: Any]] = []

        URLProtocolStub.requestHandler = { request in
            if request.url?.path == "/v1/chat/completions" {
                let data = try XCTUnwrap(request.bodyData)
                requestBodies.append(try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]))
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
            messages: [LLMMessage(role: .user, content: [.text("presence")])],
            responseFormat: .userPresenceEvaluation
        )
        _ = try await engine.complete(
            messages: [LLMMessage(role: .user, content: [.text("task")])],
            responseFormat: .taskAlignmentEvaluation
        )
        _ = try await engine.complete(
            messages: [LLMMessage(role: .user, content: [.text("progress")])],
            responseFormat: .taskProgressEvaluation
        )
        _ = try await engine.complete(
            messages: [LLMMessage(role: .user, content: [.text("target")])],
            responseFormat: .taskRelevantTargetEvaluation
        )

        let presenceBody = try XCTUnwrap(requestBodies.first)
        XCTAssertEqual(presenceBody["max_tokens"] as? Int, 180)
        let presenceFormat = try XCTUnwrap(presenceBody["response_format"] as? [String: Any])
        let presenceSchema = try XCTUnwrap(presenceFormat["json_schema"] as? [String: Any])
        XCTAssertEqual(presenceSchema["name"] as? String, "user_presence_evaluation")
        let presenceProperties = try XCTUnwrap((presenceSchema["schema"] as? [String: Any])?["properties"] as? [String: Any])
        XCTAssertEqual((presenceProperties["presence"] as? [String: Any])?["enum"] as? [String], ["present", "away", "resting", "unclear"])
        XCTAssertEqual((presenceProperties["engagement"] as? [String: Any])?["enum"] as? [String], ["engaged", "disengaged", "unclear"])

        let taskBody = try XCTUnwrap(requestBodies.dropFirst().first)
        XCTAssertEqual(taskBody["max_tokens"] as? Int, 220)
        let taskFormat = try XCTUnwrap(taskBody["response_format"] as? [String: Any])
        let taskSchema = try XCTUnwrap(taskFormat["json_schema"] as? [String: Any])
        XCTAssertEqual(taskSchema["name"] as? String, "task_alignment_evaluation")
        let taskProperties = try XCTUnwrap((taskSchema["schema"] as? [String: Any])?["properties"] as? [String: Any])
        XCTAssertEqual((taskProperties["alignment"] as? [String: Any])?["enum"] as? [String], ["aligned", "unaligned", "unclear"])
        XCTAssertNil(taskProperties["progress"])
        XCTAssertEqual((taskProperties["focusTargetID"] as? [String: Any])?["type"] as? [String], ["string", "null"])

        let progressBody = try XCTUnwrap(requestBodies.dropFirst(2).first)
        XCTAssertEqual(progressBody["max_tokens"] as? Int, 220)
        let progressFormat = try XCTUnwrap(progressBody["response_format"] as? [String: Any])
        let progressSchema = try XCTUnwrap(progressFormat["json_schema"] as? [String: Any])
        XCTAssertEqual(progressSchema["name"] as? String, "task_progress_evaluation")
        let progressProperties = try XCTUnwrap((progressSchema["schema"] as? [String: Any])?["properties"] as? [String: Any])
        XCTAssertEqual((progressProperties["progress"] as? [String: Any])?["enum"] as? [String], ["progressing", "stalled", "unclear"])
        XCTAssertEqual((progressProperties["comparisonBasis"] as? [String: Any])?["type"] as? String, "string")

        let targetBody = try XCTUnwrap(requestBodies.last)
        XCTAssertEqual(targetBody["max_tokens"] as? Int, 220)
        let targetFormat = try XCTUnwrap(targetBody["response_format"] as? [String: Any])
        let targetSchema = try XCTUnwrap(targetFormat["json_schema"] as? [String: Any])
        XCTAssertEqual(targetSchema["name"] as? String, "task_relevant_target_evaluation")
        let targetProperties = try XCTUnwrap((targetSchema["schema"] as? [String: Any])?["properties"] as? [String: Any])
        XCTAssertEqual((targetProperties["alignment"] as? [String: Any])?["enum"] as? [String], ["aligned", "unaligned", "unclear"])
        XCTAssertNil(targetProperties["focusTargetID"])
        XCTAssertEqual(((targetSchema["schema"] as? [String: Any])?["required"] as? [String]), ["alignment", "reason"])
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
        XCTAssertEqual(metrics.inputTextTokenCount, 21)
        XCTAssertNotNil(metrics.requestDurationSeconds)
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

private final class OneShotUnixSocketHTTPServer {
    private let socketURL: URL
    private let responseBody: Data?
    private let lock = NSLock()
    private var listenSocket: Int32 = -1
    private var requestData = Data()
    private var requestError: Error?

    init(socketURL: URL, responseBody: Data?) throws {
        self.socketURL = socketURL
        self.responseBody = responseBody
        try? FileManager.default.removeItem(at: socketURL)
    }

    func start() throws {
        let socketDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        listenSocket = socketDescriptor

        do {
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = Array(socketURL.path.utf8CString)
            let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
            guard pathBytes.count <= pathCapacity else {
                throw URLError(.badURL)
            }
            _ = socketURL.path.withCString { source in
                withUnsafeMutablePointer(to: &address.sun_path.0) { destination in
                    strlcpy(destination, source, pathCapacity)
                }
            }
            let pathOffset = MemoryLayout<sockaddr_un>.offset(of: \.sun_path) ?? 0
            address.sun_len = UInt8(pathOffset + pathBytes.count)
            let addressLength = socklen_t(address.sun_len)
            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    bind(socketDescriptor, sockaddrPointer, addressLength)
                }
            }
            guard bindResult == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard listen(socketDescriptor, 1) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            stop()
            throw error
        }

        Thread.detachNewThread { [weak self] in
            self?.acceptOneRequest()
        }
    }

    func stop() {
        if listenSocket >= 0 {
            close(listenSocket)
            listenSocket = -1
        }
        try? FileManager.default.removeItem(at: socketURL)
    }

    func capturedRequestText() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        if let requestError {
            throw requestError
        }
        return String(decoding: requestData, as: UTF8.self)
    }

    private func acceptOneRequest() {
        let clientSocket = accept(listenSocket, nil, nil)
        guard clientSocket >= 0 else {
            record(error: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO))
            return
        }
        defer { close(clientSocket) }

        do {
            let request = try readHTTPRequest(from: clientSocket)
            record(request: request)
            guard let responseBody else {
                Thread.sleep(forTimeInterval: 1)
                return
            }
            let header = "HTTP/1.1 200 OK\r\n"
                + "Content-Type: application/json\r\n"
                + "Content-Length: \(responseBody.count)\r\n"
                + "Connection: close\r\n"
                + "\r\n"
            try writeAll(Data(header.utf8) + responseBody, to: clientSocket)
        } catch {
            record(error: error)
        }
    }

    private func readHTTPRequest(from socketDescriptor: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = recv(socketDescriptor, &buffer, buffer.count, 0)
            if count > 0 {
                data.append(buffer, count: count)
                if let headerRange = data.range(of: Data("\r\n\r\n".utf8)) {
                    let bodyStart = headerRange.upperBound
                    let headerText = String(decoding: data[..<headerRange.lowerBound], as: UTF8.self)
                    let contentLength = Self.contentLength(from: headerText)
                    if data.count >= bodyStart + contentLength {
                        return data
                    }
                }
            } else if count == 0 {
                return data
            } else if errno == EINTR {
                continue
            } else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }

    private func writeAll(_ data: Data, to socketDescriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = send(socketDescriptor, baseAddress.advanced(by: offset), buffer.count - offset, 0)
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            }
        }
    }

    private func record(request: Data) {
        lock.lock()
        requestData = request
        lock.unlock()
    }

    private func record(error: Error) {
        lock.lock()
        requestError = error
        lock.unlock()
    }

    private static func contentLength(from headerText: String) -> Int {
        for line in headerText.components(separatedBy: "\r\n") {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.caseInsensitiveCompare("Content-Length") == .orderedSame else { continue }
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(value) ?? 0
        }
        return 0
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
