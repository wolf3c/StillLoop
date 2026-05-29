import Foundation
import StillLoopCore

protocol OpenAICompatibleHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

private struct URLSessionOpenAICompatibleHTTPTransport: OpenAICompatibleHTTPTransport {
    var session: URLSession

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

final class UnixSocketOpenAICompatibleHTTPTransport: OpenAICompatibleHTTPTransport {
    private let socketURL: URL

    init(socketURL: URL) {
        self.socketURL = socketURL
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try perform(request)
    }

    private func perform(_ request: URLRequest) throws -> (Data, URLResponse) {
        let socketDescriptor = try connectSocket()
        defer { close(socketDescriptor) }

        try setSocketTimeouts(socketDescriptor, timeout: request.timeoutInterval)
        try writeAll(requestData(for: request), to: socketDescriptor)
        let responseData = try readAll(from: socketDescriptor)
        return try parseHTTPResponse(responseData, requestURL: request.url)
    }

    private func connectSocket() throws -> Int32 {
        let socketDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

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
            let connectResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    connect(socketDescriptor, sockaddrPointer, addressLength)
                }
            }
            guard connectResult == 0 else {
                throw socketError()
            }
            return socketDescriptor
        } catch {
            close(socketDescriptor)
            throw error
        }
    }

    private func setSocketTimeouts(_ socketDescriptor: Int32, timeout: TimeInterval) throws {
        guard timeout > 0 else { return }
        var value = timeval(
            tv_sec: __darwin_time_t(timeout.rounded(.down)),
            tv_usec: __darwin_suseconds_t((timeout.truncatingRemainder(dividingBy: 1)) * 1_000_000)
        )
        let length = socklen_t(MemoryLayout<timeval>.size)
        let receiveResult = withUnsafePointer(to: &value) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<timeval>.size) { reboundPointer in
                setsockopt(socketDescriptor, SOL_SOCKET, SO_RCVTIMEO, reboundPointer, length)
            }
        }
        guard receiveResult == 0 else {
            throw socketError()
        }
        let sendResult = withUnsafePointer(to: &value) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<timeval>.size) { reboundPointer in
                setsockopt(socketDescriptor, SOL_SOCKET, SO_SNDTIMEO, reboundPointer, length)
            }
        }
        guard sendResult == 0 else {
            throw socketError()
        }
    }

    private func requestData(for request: URLRequest) throws -> Data {
        guard let url = request.url else {
            throw URLError(.badURL)
        }
        let method = request.httpMethod ?? "GET"
        let path = url.path.isEmpty ? "/" : url.path
        let pathAndQuery = url.query.map { "\(path)?\($0)" } ?? path
        let body = try httpBodyData(for: request)
        var lines = [
            "\(method) \(pathAndQuery) HTTP/1.1",
            "Host: localhost",
            "Connection: close"
        ]
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            let normalizedKey = key.lowercased()
            guard normalizedKey != "host",
                  normalizedKey != "connection",
                  normalizedKey != "content-length"
            else {
                continue
            }
            lines.append("\(key): \(value)")
        }
        if !body.isEmpty {
            lines.append("Content-Length: \(body.count)")
        }
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8) + body
    }

    private func httpBodyData(for request: URLRequest) throws -> Data {
        if let httpBody = request.httpBody {
            return httpBody
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 16_384
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count > 0 {
                data.append(buffer, count: count)
            } else if count < 0 {
                throw stream.streamError ?? URLError(.cannotDecodeRawData)
            } else {
                break
            }
        }
        return data
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
                    throw socketError()
                }
            }
        }
    }

    private func readAll(from socketDescriptor: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = recv(socketDescriptor, &buffer, buffer.count, 0)
            if count > 0 {
                data.append(buffer, count: count)
            } else if count == 0 {
                return data
            } else if errno == EINTR {
                continue
            } else {
                throw socketError()
            }
        }
    }

    private func parseHTTPResponse(_ responseData: Data, requestURL: URL?) throws -> (Data, URLResponse) {
        guard
            let headerRange = responseData.range(of: Data("\r\n\r\n".utf8)),
            let headerText = String(data: responseData[..<headerRange.lowerBound], encoding: .utf8)
        else {
            throw URLError(.badServerResponse)
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard
            let statusLine = lines.first,
            let statusCodeText = statusLine.split(separator: " ", maxSplits: 2).dropFirst().first,
            let statusCode = Int(statusCodeText)
        else {
            throw URLError(.badServerResponse)
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator])
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let rawBody = responseData[headerRange.upperBound...]
        let body = try decodedBody(rawBody, headers: headers)
        guard
            let url = requestURL,
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
        else {
            throw URLError(.badServerResponse)
        }
        return (body, response)
    }

    private func decodedBody(_ rawBody: Data.SubSequence, headers: [String: String]) throws -> Data {
        if headerValue("Transfer-Encoding", in: headers)?.lowercased().contains("chunked") == true {
            return try decodeChunkedBody(Data(rawBody))
        }
        if let contentLengthText = headerValue("Content-Length", in: headers),
           let contentLength = Int(contentLengthText),
           rawBody.count >= contentLength {
            return Data(rawBody.prefix(contentLength))
        }
        return Data(rawBody)
    }

    private func decodeChunkedBody(_ data: Data) throws -> Data {
        var decoded = Data()
        var offset = data.startIndex
        let newline = Data("\r\n".utf8)

        while offset < data.endIndex {
            guard let sizeRange = data.range(of: newline, in: offset..<data.endIndex) else {
                throw URLError(.badServerResponse)
            }
            let sizeLine = String(decoding: data[offset..<sizeRange.lowerBound], as: UTF8.self)
                .split(separator: ";", maxSplits: 1)
                .first
                .map(String.init) ?? ""
            guard let size = Int(sizeLine.trimmingCharacters(in: .whitespacesAndNewlines), radix: 16) else {
                throw URLError(.badServerResponse)
            }
            offset = sizeRange.upperBound
            if size == 0 {
                return decoded
            }
            let chunkEnd = offset + size
            guard chunkEnd <= data.endIndex else {
                throw URLError(.badServerResponse)
            }
            decoded.append(data[offset..<chunkEnd])
            offset = chunkEnd
            guard data.range(of: newline, in: offset..<min(offset + newline.count, data.endIndex)) != nil else {
                throw URLError(.badServerResponse)
            }
            offset += newline.count
        }

        return decoded
    }

    private func headerValue(_ key: String, in headers: [String: String]) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    private func socketError() -> Error {
        if errno == EAGAIN || errno == EWOULDBLOCK {
            return URLError(.timedOut)
        }
        return POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

final class OpenAICompatibleLLMEngine: StructuredLocalLLMEngine, LLMRequestTransportMetricsProviding, LLMInputTextTokenCounting, LLMFocusPromptCachePrewarming, LLMFocusPromptCacheProbing {
    struct HTTPStatusError: LLMHTTPStatusErrorReporting, Equatable {
        var statusCode: Int
        var responseByteCount: Int
    }

    private static let defaultMaxTokens = 900
    private static let focusEvaluationMaxTokens = 420
    private static let userPresenceEvaluationMaxTokens = 180
    private static let taskAlignmentEvaluationMaxTokens = 220
    private static let unixSocketScheme = "http+unix"

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

    struct LlamaServerRequestOptions: Equatable {
        var slotID: Int
        var cachePrompt: Bool

        init(slotID: Int, cachePrompt: Bool = true) {
            self.slotID = slotID
            self.cachePrompt = cachePrompt
        }
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
    private let transport: OpenAICompatibleHTTPTransport
    private let disablesReasoning: Bool
    private let usesResponseFormat: Bool
    private let llamaServerRequestOptions: LlamaServerRequestOptions?
    private(set) var lastRequestTransportMetrics: LLMRequestTransportMetrics?

    init(
        baseURL: URL,
        model: String,
        apiKey: String? = nil,
        disablesReasoning: Bool = false,
        usesResponseFormat: Bool = false,
        llamaServerRequestOptions: LlamaServerRequestOptions? = nil,
        session: URLSession = .shared,
        transport: OpenAICompatibleHTTPTransport? = nil
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if let transport {
            self.transport = transport
        } else if let socketURL = Self.unixSocketURL(from: baseURL) {
            self.transport = UnixSocketOpenAICompatibleHTTPTransport(socketURL: socketURL)
        } else {
            self.transport = URLSessionOpenAICompatibleHTTPTransport(session: session)
        }
        self.disablesReasoning = disablesReasoning
        self.usesResponseFormat = usesResponseFormat
        self.llamaServerRequestOptions = llamaServerRequestOptions
    }

    static func unixSocketBaseURL(socketURL: URL) -> URL {
        let socketPath = socketURL.path
        let encodedPath = socketPath.utf8.map { String(format: "%02x", $0) }.joined()
        return URL(string: "\(unixSocketScheme)://\(encodedPath)/v1")!
    }

    static func unixSocketURL(from baseURL: URL) -> URL? {
        guard
            baseURL.scheme == unixSocketScheme,
            let encodedPath = baseURL.host,
            encodedPath.count.isMultiple(of: 2)
        else {
            return nil
        }

        var bytes: [UInt8] = []
        var index = encodedPath.startIndex
        while index < encodedPath.endIndex {
            let nextIndex = encodedPath.index(index, offsetBy: 2)
            guard let byte = UInt8(encodedPath[index..<nextIndex], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = nextIndex
        }
        guard let path = String(bytes: bytes, encoding: .utf8), !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
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
        let (data, response) = try await transport.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPStatusError(statusCode: http.statusCode, responseByteCount: data.count)
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
            inputTextTokenCount: body.usage?.diagnosticInt(at: ["prompt_tokens"]),
            requestDurationSeconds: result.requestDurationSeconds,
            llamaServerSlotID: llamaServerRequestOptions?.slotID,
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
            maxTokens: Self.maxTokens(for: responseFormat)
        )
        let body = try JSONDecoder().decode(ResponseBody.self, from: result.data)
        guard let content = body.choices.first?.message.content else {
            throw URLError(.cannotParseResponse)
        }
        lastRequestTransportMetrics = LLMRequestTransportMetrics(
            payloadBytes: result.payloadBytes,
            responseChars: content.count,
            inputTextTokenCount: body.usage?.diagnosticInt(at: ["prompt_tokens"]),
            requestDurationSeconds: result.requestDurationSeconds,
            llamaServerSlotID: llamaServerRequestOptions?.slotID,
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
    ) async throws -> (data: Data, payloadBytes: Int, requestDurationSeconds: TimeInterval) {
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

        let startedAt = Date()
        let (data, response) = try await transport.data(for: request)
        let requestDurationSeconds = max(0, Date().timeIntervalSince(startedAt))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPStatusError(statusCode: http.statusCode, responseByteCount: data.count)
        }
        return (data, payload.count, requestDurationSeconds)
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
            ("min_p", .number("0.0")),
            ("presence_penalty", .number("1.5")),
            ("repeat_penalty", .number("1.0")),
            ("max_tokens", .number("\(maxTokens)")),
            ("stream", .bool(false))
        ]
        if disablesReasoning {
            fields.append(("chat_template_kwargs", .object([
                ("enable_thinking", .bool(false))
            ])))
        }
        if usesResponseFormat, let responseFormat {
            fields.append(("response_format", Self.responseFormatJSON(for: responseFormat)))
        }
        if let llamaServerRequestOptions {
            fields.append(("id_slot", .number("\(llamaServerRequestOptions.slotID)")))
            fields.append(("cache_prompt", .bool(llamaServerRequestOptions.cachePrompt)))
        }
        return try OrderedJSONValue.object(fields).encodedData()
    }

    private static func maxTokens(for responseFormat: LLMResponseFormat?) -> Int {
        switch responseFormat {
        case .focusEvaluation:
            return focusEvaluationMaxTokens
        case .userPresenceEvaluation:
            return userPresenceEvaluationMaxTokens
        case .taskAlignmentEvaluation:
            return taskAlignmentEvaluationMaxTokens
        case .taskProgressEvaluation:
            return taskAlignmentEvaluationMaxTokens
        case .taskRelevantTargetEvaluation:
            return taskAlignmentEvaluationMaxTokens
        case nil:
            return defaultMaxTokens
        }
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

    private static func responseFormatJSON(for responseFormat: LLMResponseFormat) -> OrderedJSONValue {
        switch responseFormat {
        case .focusEvaluation:
            return focusEvaluationResponseFormatJSON()
        case .userPresenceEvaluation:
            return userPresenceEvaluationResponseFormatJSON()
        case .taskAlignmentEvaluation:
            return taskAlignmentEvaluationResponseFormatJSON()
        case .taskProgressEvaluation:
            return taskProgressEvaluationResponseFormatJSON()
        case .taskRelevantTargetEvaluation:
            return taskRelevantTargetEvaluationResponseFormatJSON()
        }
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
                        ("focusTargetID", .object([
                            ("type", .array([.string("string"), .string("null")]))
                        ])),
                        ("nudge", .object([("type", .array([.string("string"), .string("null")]))]))
                    ])),
                    ("required", .array([
                        .string("analysis"),
                        .string("reason"),
                        .string("state"),
                        .string("focusTargetID"),
                        .string("nudge")
                    ]))
                ]))
            ]))
        ])
    }

    private static func userPresenceEvaluationResponseFormatJSON() -> OrderedJSONValue {
        .object([
            ("type", .string("json_schema")),
            ("json_schema", .object([
                ("name", .string("user_presence_evaluation")),
                ("strict", .bool(true)),
                ("schema", .object([
                    ("type", .string("object")),
                    ("additionalProperties", .bool(false)),
                    ("properties", .object([
                        ("presence", .object([
                            ("type", .string("string")),
                            ("enum", .array([
                                .string("present"),
                                .string("away"),
                                .string("resting"),
                                .string("unclear")
                            ]))
                        ])),
                        ("engagement", .object([
                            ("type", .string("string")),
                            ("enum", .array([
                                .string("engaged"),
                                .string("disengaged"),
                                .string("unclear")
                            ]))
                        ])),
                        ("reason", .object([("type", .string("string"))]))
                    ])),
                    ("required", .array([
                        .string("presence"),
                        .string("engagement"),
                        .string("reason")
                    ]))
                ]))
            ]))
        ])
    }

    private static func taskAlignmentEvaluationResponseFormatJSON() -> OrderedJSONValue {
        .object([
            ("type", .string("json_schema")),
            ("json_schema", .object([
                ("name", .string("task_alignment_evaluation")),
                ("strict", .bool(true)),
                ("schema", .object([
                    ("type", .string("object")),
                    ("additionalProperties", .bool(false)),
                    ("properties", .object([
                        ("alignment", .object([
                            ("type", .string("string")),
                            ("enum", .array([
                                .string("aligned"),
                                .string("unaligned"),
                                .string("unclear")
                            ]))
                        ])),
                        ("focusTargetID", .object([
                            ("type", .array([.string("string"), .string("null")]))
                        ])),
                        ("reason", .object([("type", .string("string"))]))
                    ])),
                    ("required", .array([
                        .string("alignment"),
                        .string("focusTargetID"),
                        .string("reason")
                    ]))
                ]))
            ]))
        ])
    }

    private static func taskProgressEvaluationResponseFormatJSON() -> OrderedJSONValue {
        .object([
            ("type", .string("json_schema")),
            ("json_schema", .object([
                ("name", .string("task_progress_evaluation")),
                ("strict", .bool(true)),
                ("schema", .object([
                    ("type", .string("object")),
                    ("additionalProperties", .bool(false)),
                    ("properties", .object([
                        ("progress", .object([
                            ("type", .string("string")),
                            ("enum", .array([
                                .string("progressing"),
                                .string("stalled"),
                                .string("unclear")
                            ]))
                        ])),
                        ("comparisonBasis", .object([("type", .string("string"))])),
                        ("reason", .object([("type", .string("string"))]))
                    ])),
                    ("required", .array([
                        .string("progress"),
                        .string("comparisonBasis"),
                        .string("reason")
                    ]))
                ]))
            ]))
        ])
    }

    private static func taskRelevantTargetEvaluationResponseFormatJSON() -> OrderedJSONValue {
        .object([
            ("type", .string("json_schema")),
            ("json_schema", .object([
                ("name", .string("task_relevant_target_evaluation")),
                ("strict", .bool(true)),
                ("schema", .object([
                    ("type", .string("object")),
                    ("additionalProperties", .bool(false)),
                    ("properties", .object([
                        ("alignment", .object([
                            ("type", .string("string")),
                            ("enum", .array([
                                .string("aligned"),
                                .string("unaligned"),
                                .string("unclear")
                            ]))
                        ])),
                        ("reason", .object([("type", .string("string"))]))
                    ])),
                    ("required", .array([
                        .string("alignment"),
                        .string("reason")
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
            let (data, response) = try await transport.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try JSONDecoder().decode(TokenizeResponse.self, from: data).tokens.count
        } catch {
            return nil
        }
    }

    private var isLocalBaseURL: Bool {
        if baseURL.scheme == Self.unixSocketScheme {
            return true
        }
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
