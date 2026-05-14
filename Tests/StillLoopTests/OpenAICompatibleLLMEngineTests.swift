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
