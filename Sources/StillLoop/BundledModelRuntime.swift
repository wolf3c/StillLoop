import Darwin
import Foundation
import StillLoopCore

protocol BundledModelRuntimeManaging: AnyObject {
    var baseURL: URL { get }
    var modelID: String { get }
    var state: BundledModelRuntime.State { get }

    func startIfNeeded() async throws
    func stop()
}

enum BundledRuntimeKind: String, Equatable {
    case mlx
    case rapidMlx
    case llamaCpp
}

protocol BundledRuntimeDiagnosticsProviding: AnyObject {
    var bundledRuntimeKind: BundledRuntimeKind? { get }
    var fallbackRuntimeKind: BundledRuntimeKind? { get }
    var mlxAPCEnabled: Bool? { get }
}

extension BundledRuntimeDiagnosticsProviding {
    var mlxAPCEnabled: Bool? { nil }
}

protocol BundledModelProcessManaging: AnyObject {
    var isRunning: Bool { get }
    var processIdentifier: Int32 { get }
    func terminate()
}

protocol BundledModelProcessLaunching {
    func launch(executableURL: URL, arguments: [String]) throws -> BundledModelProcessManaging
}

struct MLXRuntimeCacheTuning: Equatable {
    var apcEnabled: Bool

    static let defaultValue = MLXRuntimeCacheTuning(apcEnabled: true)

    var environmentArguments: [String] {
        apcEnabled ? ["APC_ENABLED=1"] : []
    }
}

struct BundledModelPortOccupant: Equatable {
    var pid: Int32
    var executablePath: String
    var arguments: [String]
}

struct BundledRuntimeSelection {
    static let defaultKind: BundledRuntimeKind = .llamaCpp
    static let rapidMLXDefaultModelIdentifier = "mlx-community/Qwen3.5-0.8B-4bit"

    static func makeDefaultRuntime(
        kind: BundledRuntimeKind,
        modelURL: URL,
        bundle: Bundle = .main,
        rapidMLXModelIdentifier: String = rapidMLXDefaultModelIdentifier
    ) -> BundledModelRuntimeManaging {
        switch kind {
        case .mlx:
            return FallbackBundledModelRuntime(
                primary: makeRuntime(kind: .mlx, modelURL: modelURL, bundle: bundle),
                fallback: makeRuntime(kind: .llamaCpp, modelURL: modelURL, bundle: bundle)
            )
        case .rapidMlx:
            return FallbackBundledModelRuntime(
                primary: makeRuntime(
                    kind: .rapidMlx,
                    modelURL: modelURL,
                    bundle: bundle,
                    rapidMLXModelIdentifier: rapidMLXModelIdentifier
                ),
                fallback: makeRuntime(kind: .llamaCpp, modelURL: modelURL, bundle: bundle)
            )
        case .llamaCpp:
            return makeRuntime(kind: .llamaCpp, modelURL: modelURL, bundle: bundle)
        }
    }

    static func makeDefaultRuntime(
        modelURL: URL,
        bundle: Bundle = .main
    ) -> BundledModelRuntimeManaging {
        makeDefaultRuntime(kind: defaultKind, modelURL: modelURL, bundle: bundle)
    }

    static func runtimeKind(
        environment: [String: String]
    ) -> BundledRuntimeKind {
        guard let rawValue = environment["STILLLOOP_BUNDLED_RUNTIME"] else {
            return defaultKind
        }
        return BundledRuntimeKind(rawValue: rawValue) ?? defaultKind
    }

    static func makeRuntime(
        kind: BundledRuntimeKind,
        modelURL: URL,
        bundle: Bundle = .main,
        rapidMLXModelIdentifier: String = rapidMLXDefaultModelIdentifier
    ) -> BundledModelRuntimeManaging {
        switch kind {
        case .mlx:
            return MLXBundledModelRuntime.defaultRuntime()
        case .rapidMlx:
            return RapidMLXBundledModelRuntime.defaultRuntime(
                modelIdentifier: rapidMLXModelIdentifier
            )
        case .llamaCpp:
            return BundledModelRuntime.defaultRuntime(modelURL: modelURL, bundle: bundle)
        }
    }
}

final class FallbackBundledModelRuntime: BundledModelRuntimeManaging, BundledRuntimeDiagnosticsProviding {
    private let primaryRuntime: BundledModelRuntimeManaging
    private let fallbackRuntime: BundledModelRuntimeManaging
    private var activeRuntime: BundledModelRuntimeManaging?
    private(set) var fallbackRuntimeKind: BundledRuntimeKind?

    private(set) var baseURL: URL
    private(set) var modelID: String
    private(set) var state: BundledModelRuntime.State = .notStarted

    init(
        primary: BundledModelRuntimeManaging,
        fallback: BundledModelRuntimeManaging
    ) {
        primaryRuntime = primary
        fallbackRuntime = fallback
        baseURL = primary.baseURL
        modelID = primary.modelID
    }

    var bundledRuntimeKind: BundledRuntimeKind? {
        if let activeRuntime {
            return (activeRuntime as? BundledRuntimeDiagnosticsProviding)?.bundledRuntimeKind
        }
        if fallbackRuntimeKind != nil {
            return (fallbackRuntime as? BundledRuntimeDiagnosticsProviding)?.bundledRuntimeKind
        }
        return (primaryRuntime as? BundledRuntimeDiagnosticsProviding)?.bundledRuntimeKind
    }

    var mlxAPCEnabled: Bool? {
        if let activeRuntime {
            return (activeRuntime as? BundledRuntimeDiagnosticsProviding)?.mlxAPCEnabled
        }
        if fallbackRuntimeKind != nil {
            return (fallbackRuntime as? BundledRuntimeDiagnosticsProviding)?.mlxAPCEnabled
        }
        return (primaryRuntime as? BundledRuntimeDiagnosticsProviding)?.mlxAPCEnabled
    }

    func startIfNeeded() async throws {
        if activeRuntime === fallbackRuntime {
            try await startFallback()
            return
        }

        do {
            try await primaryRuntime.startIfNeeded()
            activeRuntime = primaryRuntime
            fallbackRuntimeKind = nil
            updateRuntimeState(from: primaryRuntime)
        } catch {
            primaryRuntime.stop()
            try await startFallback()
        }
    }

    func stop() {
        primaryRuntime.stop()
        fallbackRuntime.stop()
        activeRuntime = nil
        fallbackRuntimeKind = nil
        baseURL = primaryRuntime.baseURL
        modelID = primaryRuntime.modelID
        state = .stopped
    }

    private func startFallback() async throws {
        fallbackRuntimeKind = (fallbackRuntime as? BundledRuntimeDiagnosticsProviding)?.bundledRuntimeKind
        do {
            try await fallbackRuntime.startIfNeeded()
            activeRuntime = fallbackRuntime
            updateRuntimeState(from: fallbackRuntime)
        } catch {
            activeRuntime = fallbackRuntime
            updateRuntimeState(from: fallbackRuntime)
            throw error
        }
    }

    private func updateRuntimeState(from runtime: BundledModelRuntimeManaging) {
        baseURL = runtime.baseURL
        modelID = runtime.modelID
        state = runtime.state
    }
}

final class MLXBundledModelRuntime: BundledModelRuntimeManaging, BundledRuntimeDiagnosticsProviding {
    struct Configuration: Equatable {
        var executableURL: URL
        var arguments: [String]
        var baseURL: URL
        var modelID: String
        var cacheTuning: MLXRuntimeCacheTuning

        static func localDevelopment(
            port: Int = MLXBundledModelRuntime.availableLocalPort(),
            cacheTuning: MLXRuntimeCacheTuning = .defaultValue
        ) -> Configuration {
            let modelID = "mlx-community/Qwen3.5-0.8B-4bit"
            return Configuration(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: cacheTuning.environmentArguments + [
                    "python3",
                    "-m", "mlx_vlm.server",
                    "--host", "127.0.0.1",
                    "--port", String(port),
                    "--model", modelID,
                    "--max-tokens", "900"
                ],
                baseURL: URL(string: "http://127.0.0.1:\(port)/v1")!,
                modelID: modelID,
                cacheTuning: cacheTuning
            )
        }
    }

    let bundledRuntimeKind: BundledRuntimeKind? = .mlx
    let fallbackRuntimeKind: BundledRuntimeKind? = nil
    var mlxAPCEnabled: Bool? { configuration.cacheTuning.apcEnabled }
    let modelID: String
    private(set) var baseURL: URL
    private(set) var state: BundledModelRuntime.State = .notStarted

    private let configuration: Configuration
    private let processLauncher: BundledModelProcessLaunching
    private let readinessProbe: (URL, String) async throws -> BundledModelRuntime.Readiness
    private let readinessMaxAttempts: Int
    private let readinessRetryDelayNanoseconds: UInt64
    private let processExitMaxAttempts: Int
    private let processExitRetryDelayNanoseconds: UInt64
    private var process: BundledModelProcessManaging?

    init(
        configuration: Configuration,
        processLauncher: BundledModelProcessLaunching = FoundationBundledModelProcessLauncher(),
        readinessProbe: @escaping (URL, String) async throws -> BundledModelRuntime.Readiness = MLXBundledModelRuntime.defaultReadinessProbe,
        readinessMaxAttempts: Int = 90,
        readinessRetryDelayNanoseconds: UInt64 = 500_000_000,
        processExitMaxAttempts: Int = 20,
        processExitRetryDelayNanoseconds: UInt64 = 100_000_000
    ) {
        self.configuration = configuration
        self.processLauncher = processLauncher
        self.readinessProbe = readinessProbe
        self.readinessMaxAttempts = readinessMaxAttempts
        self.readinessRetryDelayNanoseconds = readinessRetryDelayNanoseconds
        self.processExitMaxAttempts = processExitMaxAttempts
        self.processExitRetryDelayNanoseconds = processExitRetryDelayNanoseconds
        baseURL = configuration.baseURL
        modelID = configuration.modelID
    }

    static func defaultRuntime() -> MLXBundledModelRuntime {
        MLXBundledModelRuntime(configuration: .localDevelopment())
    }

    func startIfNeeded() async throws {
        if let process, process.isRunning {
            if state == .running {
                return
            }
            do {
                _ = try await waitUntilReady()
                state = .running
                return
            } catch {
                guard await stopOwnedProcess() else {
                    let error = BundledModelRuntime.RuntimeError.launchFailed("existing mlx-vlm process did not exit")
                    state = .failed(BundledModelRuntime.RuntimeError.statusMessage(for: error))
                    throw error
                }
            }
        }

        state = .starting
        do {
            process = try processLauncher.launch(
                executableURL: configuration.executableURL,
                arguments: configuration.arguments
            )
            _ = try await waitUntilReady()
            state = .running
        } catch {
            _ = await stopOwnedProcess()
            let message = BundledModelRuntime.RuntimeError.statusMessage(for: error)
            state = .failed(message)
            if let runtimeError = error as? BundledModelRuntime.RuntimeError {
                throw runtimeError
            }
            throw BundledModelRuntime.RuntimeError.readinessFailed(String(describing: error))
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        state = .stopped
    }

    deinit {
        stop()
    }

    private func waitUntilReady() async throws -> BundledModelRuntime.Readiness {
        let attempts = max(1, readinessMaxAttempts)
        var lastError: Error?
        for attempt in 1...attempts {
            do {
                return try await readinessProbe(baseURL, modelID)
            } catch BundledModelRuntime.RuntimeError.imageInputUnavailable {
                throw BundledModelRuntime.RuntimeError.imageInputUnavailable
            } catch {
                if let process, !process.isRunning {
                    throw BundledModelRuntime.RuntimeError.launchFailed("mlx-vlm process exited before readiness")
                }
                lastError = error
                if attempt < attempts {
                    try await Task.sleep(nanoseconds: readinessRetryDelayNanoseconds)
                }
            }
        }
        if let runtimeError = lastError as? BundledModelRuntime.RuntimeError {
            throw runtimeError
        }
        throw BundledModelRuntime.RuntimeError.readinessFailed(String(describing: lastError ?? URLError(.timedOut)))
    }

    @discardableResult
    private func stopOwnedProcess() async -> Bool {
        guard let process else { return true }
        process.terminate()
        for _ in 0..<max(0, processExitMaxAttempts) {
            guard process.isRunning else { break }
            try? await Task.sleep(nanoseconds: processExitRetryDelayNanoseconds)
        }
        guard !process.isRunning else {
            state = .running
            return false
        }
        self.process = nil
        state = .stopped
        return true
    }

    private static func defaultReadinessProbe(baseURL: URL, modelID: String) async throws -> BundledModelRuntime.Readiness {
        let engine = OpenAICompatibleLLMEngine(
            baseURL: baseURL,
            model: modelID,
            disablesReasoning: true,
            usesResponseFormat: true
        )
        do {
            _ = try await engine.checkModelReadiness(requiresImageInput: true)
            return .ready
        } catch OpenAICompatibleLLMEngine.ReadinessError.imageInputUnavailable {
            throw BundledModelRuntime.RuntimeError.imageInputUnavailable
        } catch {
            throw BundledModelRuntime.RuntimeError.readinessFailed(String(describing: error))
        }
    }

    private static func availableLocalPort() -> Int {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { return 17645 }
        defer { close(socketDescriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: UInt32(INADDR_LOOPBACK).bigEndian)
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(socketDescriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return 17645 }

        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(socketDescriptor, sockaddrPointer, &length)
            }
        }
        guard nameResult == 0 else { return 17645 }
        return Int(UInt16(bigEndian: boundAddress.sin_port))
    }
}

final class RapidMLXBundledModelRuntime: BundledModelRuntimeManaging, BundledRuntimeDiagnosticsProviding {
    struct Configuration: Equatable {
        var executableURL: URL
        var arguments: [String]
        var baseURL: URL
        var modelID: String

        static func localDevelopment(
            port: Int = RapidMLXBundledModelRuntime.availableLocalPort(),
            modelIdentifier: String = BundledRuntimeSelection.rapidMLXDefaultModelIdentifier,
            executableURL: URL = Configuration.defaultExecutableURL()
        ) -> Configuration {
            let modelID = modelIdentifier
            let isWrapperCommand = executableURL.path == "/usr/bin/env"
            let commandArguments = [
                "serve",
                modelID,
                "--mllm",
                "--host", "127.0.0.1",
                "--port", String(port),
                "--max-tokens", "900"
            ]
            let invocationArguments = isWrapperCommand
                ? ["rapid-mlx"] + commandArguments
                : commandArguments
            return Configuration(
                executableURL: executableURL,
                arguments: invocationArguments,
                baseURL: URL(string: "http://127.0.0.1:\(port)/v1")!,
                modelID: modelID
            )
        }

        static func defaultExecutableURL() -> URL {
            if let explicitPath = ProcessInfo.processInfo.environment["STILLLOOP_RAPID_MLX_EXECUTABLE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !explicitPath.isEmpty,
               FileManager.default.isExecutableFile(atPath: explicitPath)
            {
                return URL(fileURLWithPath: explicitPath)
            }
            return URL(fileURLWithPath: "/usr/bin/env")
        }
    }

    let bundledRuntimeKind: BundledRuntimeKind? = .rapidMlx
    let fallbackRuntimeKind: BundledRuntimeKind? = nil
    let modelID: String
    private(set) var baseURL: URL
    private(set) var state: BundledModelRuntime.State = .notStarted

    private let configuration: Configuration
    private let processLauncher: BundledModelProcessLaunching
    private let readinessProbe: (URL, String) async throws -> BundledModelRuntime.Readiness
    private let readinessMaxAttempts: Int
    private let readinessRetryDelayNanoseconds: UInt64
    private let processExitMaxAttempts: Int
    private let processExitRetryDelayNanoseconds: UInt64
    private var process: BundledModelProcessManaging?

    init(
        configuration: Configuration,
        processLauncher: BundledModelProcessLaunching = FoundationBundledModelProcessLauncher(),
        readinessProbe: @escaping (URL, String) async throws -> BundledModelRuntime.Readiness = RapidMLXBundledModelRuntime.defaultReadinessProbe,
        readinessMaxAttempts: Int = 90,
        readinessRetryDelayNanoseconds: UInt64 = 500_000_000,
        processExitMaxAttempts: Int = 20,
        processExitRetryDelayNanoseconds: UInt64 = 100_000_000
    ) {
        self.configuration = configuration
        self.processLauncher = processLauncher
        self.readinessProbe = readinessProbe
        self.readinessMaxAttempts = readinessMaxAttempts
        self.readinessRetryDelayNanoseconds = readinessRetryDelayNanoseconds
        self.processExitMaxAttempts = processExitMaxAttempts
        self.processExitRetryDelayNanoseconds = processExitRetryDelayNanoseconds
        baseURL = configuration.baseURL
        modelID = configuration.modelID
    }

    static func defaultRuntime() -> RapidMLXBundledModelRuntime {
        RapidMLXBundledModelRuntime(configuration: .localDevelopment())
    }

    static func defaultRuntime(
        modelIdentifier: String
    ) -> RapidMLXBundledModelRuntime {
        RapidMLXBundledModelRuntime(configuration: .localDevelopment(modelIdentifier: modelIdentifier))
    }

    func startIfNeeded() async throws {
        if let process, process.isRunning {
            if state == .running {
                return
            }
            do {
                _ = try await waitUntilReady()
                state = .running
                return
            } catch {
                guard await stopOwnedProcess() else {
                    let error = BundledModelRuntime.RuntimeError.launchFailed("existing rapid-mlx process did not exit")
                    state = .failed(BundledModelRuntime.RuntimeError.statusMessage(for: error))
                    throw error
                }
            }
        }

        state = .starting
        do {
            process = try processLauncher.launch(
                executableURL: configuration.executableURL,
                arguments: configuration.arguments
            )
            _ = try await waitUntilReady()
            state = .running
        } catch {
            _ = await stopOwnedProcess()
            let message = BundledModelRuntime.RuntimeError.statusMessage(for: error)
            state = .failed(message)
            if let runtimeError = error as? BundledModelRuntime.RuntimeError {
                throw runtimeError
            }
            throw BundledModelRuntime.RuntimeError.readinessFailed(String(describing: error))
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        state = .stopped
    }

    deinit {
        stop()
    }

    private func waitUntilReady() async throws -> BundledModelRuntime.Readiness {
        let attempts = max(1, readinessMaxAttempts)
        var lastError: Error?
        for attempt in 1...attempts {
            do {
                return try await readinessProbe(baseURL, modelID)
            } catch BundledModelRuntime.RuntimeError.imageInputUnavailable {
                throw BundledModelRuntime.RuntimeError.imageInputUnavailable
            } catch {
                if let process, !process.isRunning {
                    throw BundledModelRuntime.RuntimeError.launchFailed("rapid-mlx process exited before readiness")
                }
                lastError = error
                if attempt < attempts {
                    try await Task.sleep(nanoseconds: readinessRetryDelayNanoseconds)
                }
            }
        }
        if let runtimeError = lastError as? BundledModelRuntime.RuntimeError {
            throw runtimeError
        }
        throw BundledModelRuntime.RuntimeError.readinessFailed(String(describing: lastError ?? URLError(.timedOut)))
    }

    @discardableResult
    private func stopOwnedProcess() async -> Bool {
        guard let process else { return true }
        process.terminate()
        for _ in 0..<max(0, processExitMaxAttempts) {
            guard process.isRunning else { break }
            try? await Task.sleep(nanoseconds: processExitRetryDelayNanoseconds)
        }
        guard !process.isRunning else {
            state = .running
            return false
        }
        self.process = nil
        state = .stopped
        return true
    }

    private static func defaultReadinessProbe(baseURL: URL, modelID: String) async throws -> BundledModelRuntime.Readiness {
        let engine = OpenAICompatibleLLMEngine(
            baseURL: baseURL,
            model: modelID,
            disablesReasoning: true,
            usesResponseFormat: true
        )
        do {
            _ = try await engine.checkModelReadiness(requiresImageInput: true)
            return .ready
        } catch OpenAICompatibleLLMEngine.ReadinessError.imageInputUnavailable {
            throw BundledModelRuntime.RuntimeError.imageInputUnavailable
        } catch {
            throw BundledModelRuntime.RuntimeError.readinessFailed(String(describing: error))
        }
    }

    private static func availableLocalPort() -> Int {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { return 17645 }
        defer { close(socketDescriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: UInt32(INADDR_LOOPBACK).bigEndian)
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(socketDescriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return 17645 }

        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(socketDescriptor, sockaddrPointer, &length)
            }
        }
        guard nameResult == 0 else { return 17645 }
        return Int(UInt16(bigEndian: boundAddress.sin_port))
    }
}

final class BundledModelRuntime: BundledModelRuntimeManaging, BundledRuntimeDiagnosticsProviding {
    enum State: Equatable {
        case notStarted
        case starting
        case running
        case stopped
        case failed(String)
    }

    enum RuntimeError: Error, Equatable {
        case missingExecutable(URL)
        case missingModel(URL)
        case missingProjector(URL)
        case launchFailed(String)
        case imageInputUnavailable
        case readinessFailed(String)

        static func statusMessage(for error: Error) -> String {
            guard let runtimeError = error as? RuntimeError else {
                return "启动失败"
            }
            switch runtimeError {
            case .missingExecutable:
                return "缺少 stillloop-llama-server"
            case .missingModel:
                return "缺少模型文件"
            case .missingProjector:
                return "缺少视觉投影文件"
            case .launchFailed:
                return "启动失败"
            case .imageInputUnavailable:
                return "自带模型不支持图片输入"
            case .readinessFailed:
                return "模型探测失败"
            }
        }
    }

    enum Readiness {
        case ready
    }

    struct LaunchTuning: Equatable {
        var metricsEnabled: Bool
        var promptCacheEnabled: Bool
        var contextSize: Int?
        var parallelSlots: Int?
        var batchSize: Int?
        var microbatchSize: Int?
        var flashAttention: String?
        var promptCacheReuse: Int?
        var promptCacheRAMMiB: Int?

        static let development = LaunchTuning(metricsEnabled: true, promptCacheEnabled: false)
        static let production = LaunchTuning(metricsEnabled: false, promptCacheEnabled: false)

        init(
            metricsEnabled: Bool,
            promptCacheEnabled: Bool,
            contextSize: Int? = nil,
            parallelSlots: Int? = nil,
            batchSize: Int? = nil,
            microbatchSize: Int? = nil,
            flashAttention: String? = nil,
            promptCacheReuse: Int? = nil,
            promptCacheRAMMiB: Int? = nil
        ) {
            self.metricsEnabled = metricsEnabled
            self.promptCacheEnabled = promptCacheEnabled
            self.contextSize = contextSize
            self.parallelSlots = parallelSlots
            self.batchSize = batchSize
            self.microbatchSize = microbatchSize
            self.flashAttention = flashAttention
            self.promptCacheReuse = promptCacheReuse
            self.promptCacheRAMMiB = promptCacheRAMMiB
        }

        static var `default`: LaunchTuning {
            resolvedDefault(environment: ProcessInfo.processInfo.environment)
        }

        static func resolvedDefault(environment: [String: String]) -> LaunchTuning {
            var tuning: LaunchTuning
            #if DEBUG
            tuning = .development
            #else
            tuning = .production
            #endif
            tuning.contextSize = positiveInt("STILLLOOP_LLAMA_CTX_SIZE", environment: environment)
            tuning.parallelSlots = positiveInt("STILLLOOP_LLAMA_PARALLEL", environment: environment)
            tuning.batchSize = positiveInt("STILLLOOP_LLAMA_BATCH_SIZE", environment: environment)
            tuning.microbatchSize = positiveInt("STILLLOOP_LLAMA_UBATCH_SIZE", environment: environment)
            tuning.flashAttention = flashAttentionValue(environment["STILLLOOP_LLAMA_FLASH_ATTN"])
            if let promptCacheEnabled = boolValue(environment["STILLLOOP_LLAMA_PROMPT_CACHE"]) {
                tuning.promptCacheEnabled = promptCacheEnabled
            }
            if environment["STILLLOOP_DISABLE_PROMPT_CACHE"] == "1" {
                tuning.promptCacheEnabled = false
            }
            tuning.promptCacheReuse = positiveInt("STILLLOOP_LLAMA_CACHE_REUSE", environment: environment)
            tuning.promptCacheRAMMiB = positiveInt("STILLLOOP_LLAMA_CACHE_RAM", environment: environment)
            return tuning
        }

        private static func positiveInt(_ key: String, environment: [String: String]) -> Int? {
            guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let intValue = Int(value),
                  intValue > 0
            else {
                return nil
            }
            return intValue
        }

        private static func boolValue(_ rawValue: String?) -> Bool? {
            switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "on", "yes":
                return true
            case "0", "false", "off", "no":
                return false
            default:
                return nil
            }
        }

        private static func flashAttentionValue(_ rawValue: String?) -> String? {
            switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "on", "yes":
                return "on"
            case "0", "false", "off", "no":
                return "off"
            case "auto":
                return "auto"
            default:
                return nil
            }
        }
    }

    let modelID: String
    let bundledRuntimeKind: BundledRuntimeKind? = .llamaCpp
    let fallbackRuntimeKind: BundledRuntimeKind? = nil
    private(set) var baseURL: URL
    private(set) var state: State = .notStarted

    private let executableURL: URL
    private let modelURL: URL
    private let mmprojURL: URL?
    private let socketURL: URL
    private let spec: ModelDownloadSpec
    private let fileManager: FileManager
    private let processLauncher: BundledModelProcessLaunching
    private let helperProcesses: () -> [BundledModelPortOccupant]
    private let terminatePortOccupant: (BundledModelPortOccupant) -> Void
    private let readinessProbe: (URL, String) async throws -> Readiness
    private let readinessMaxAttempts: Int
    private let readinessRetryDelayNanoseconds: UInt64
    private let maximumResidentMemoryBytes: UInt64
    private let residentMemoryBytes: (Int32) -> UInt64?
    private let processExitMaxAttempts: Int
    private let processExitRetryDelayNanoseconds: UInt64
    private var process: BundledModelProcessManaging?

    init(
        executableURL: URL,
        modelURL: URL,
        mmprojURL: URL? = nil,
        socketURL: URL? = nil,
        spec: ModelDownloadSpec,
        fileManager: FileManager = .default,
        processLauncher: BundledModelProcessLaunching = FoundationBundledModelProcessLauncher(),
        helperProcesses: @escaping () -> [BundledModelPortOccupant] = BundledModelRuntime.runningProcesses,
        terminatePortOccupant: @escaping (BundledModelPortOccupant) -> Void = BundledModelRuntime.defaultTerminatePortOccupant,
        readinessProbe: @escaping (URL, String) async throws -> Readiness = BundledModelRuntime.defaultReadinessProbe,
        readinessMaxAttempts: Int = 60,
        readinessRetryDelayNanoseconds: UInt64 = 500_000_000,
        maximumResidentMemoryBytes: UInt64 = BundledModelRuntime.defaultMaximumResidentMemoryBytes,
        residentMemoryBytes: @escaping (Int32) -> UInt64? = BundledModelRuntime.residentMemoryBytes,
        processExitMaxAttempts: Int = 20,
        processExitRetryDelayNanoseconds: UInt64 = 100_000_000
    ) {
        self.executableURL = executableURL
        self.modelURL = modelURL
        self.mmprojURL = mmprojURL ?? spec.mmprojFilename.map { modelURL.deletingLastPathComponent().appendingPathComponent($0) }
        self.socketURL = socketURL ?? Self.defaultSocketURL()
        self.spec = spec
        self.fileManager = fileManager
        self.processLauncher = processLauncher
        self.helperProcesses = helperProcesses
        self.terminatePortOccupant = terminatePortOccupant
        self.readinessProbe = readinessProbe
        self.readinessMaxAttempts = readinessMaxAttempts
        self.readinessRetryDelayNanoseconds = readinessRetryDelayNanoseconds
        self.maximumResidentMemoryBytes = maximumResidentMemoryBytes
        self.residentMemoryBytes = residentMemoryBytes
        self.processExitMaxAttempts = processExitMaxAttempts
        self.processExitRetryDelayNanoseconds = processExitRetryDelayNanoseconds
        baseURL = OpenAICompatibleLLMEngine.unixSocketBaseURL(socketURL: self.socketURL)
        modelID = spec.localServerModelID
    }

    static func defaultRuntime(
        modelURL: URL,
        bundle: Bundle = .main
    ) -> BundledModelRuntime {
        BundledModelRuntime(
            executableURL: bundledLlamaServerURL(bundle: bundle),
            modelURL: modelURL,
            mmprojURL: ModelDownloadSpec.builtIn.mmprojFilename.map {
                modelURL.deletingLastPathComponent().appendingPathComponent($0)
            },
            spec: .builtIn
        )
    }

    static func bundledLlamaServerURL(bundle: Bundle = .main) -> URL {
        if bundle.bundleURL.pathExtension == "app" {
            return bundle.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent(Self.helperExecutableName)
        }
        if let resourceURL = bundle.resourceURL {
            return resourceURL
                .appendingPathComponent("Runtime", isDirectory: true)
                .appendingPathComponent("llama-server")
        }
        return bundle.bundleURL
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("llama-server")
    }

    static func launchArguments(
        modelURL: URL,
        mmprojURL: URL? = nil,
        spec: ModelDownloadSpec,
        port: Int? = nil,
        socketURL: URL? = nil,
        tuning: LaunchTuning = .default
    ) -> [String] {
        _ = port
        let selectedSocketURL = socketURL ?? defaultSocketURL()
        var arguments = [
            "-m", modelURL.path,
            "--host", selectedSocketURL.path,
            "--ctx-size", String(tuning.contextSize ?? spec.recommendedContextSize),
            "--parallel", String(tuning.parallelSlots ?? spec.recommendedParallelSlots),
            "--n-gpu-layers", "99",
            "--batch-size", String(tuning.batchSize ?? 4096),
            "--ubatch-size", String(tuning.microbatchSize ?? 4096),
            "--cache-type-k", spec.recommendedCacheTypeK,
            "--cache-type-v", spec.recommendedCacheTypeV,
            "--mlock"
        ]
        if let flashAttention = tuning.flashAttention {
            arguments.append(contentsOf: ["--flash-attn", flashAttention])
        }
        if tuning.promptCacheEnabled {
            arguments.append(contentsOf: [
                "--cache-prompt",
                "--cache-reuse", String(tuning.promptCacheReuse ?? spec.recommendedPromptCacheReuse),
                "--cache-ram", String(tuning.promptCacheRAMMiB ?? spec.recommendedPromptCacheRAMMiB)
            ])
        } else {
            arguments.append("--no-cache-prompt")
        }
        if let mmprojURL {
            arguments.insert(contentsOf: ["--mmproj", mmprojURL.path], at: 2)
        }
        if tuning.metricsEnabled {
            arguments.append("--metrics")
        }
        return arguments
    }

    func startIfNeeded() async throws {
        await restartForMemoryPressureIfNeeded()

        if let process, process.isRunning {
            if await canReuseExistingService(baseURL: baseURL) {
                state = .running
                return
            }
            guard await stopOwnedProcess() else {
                let error = RuntimeError.launchFailed("existing stillloop-llama-server process did not exit")
                state = .failed(RuntimeError.statusMessage(for: error))
                throw error
            }
        }

        if process?.isRunning == true {
            state = .running
            return
        }

        guard fileManager.fileExists(atPath: modelURL.path) else {
            state = .failed(RuntimeError.statusMessage(for: RuntimeError.missingModel(modelURL)))
            throw RuntimeError.missingModel(modelURL)
        }
        if let mmprojURL {
            guard fileManager.fileExists(atPath: mmprojURL.path) else {
                state = .failed(RuntimeError.statusMessage(for: RuntimeError.missingProjector(mmprojURL)))
                throw RuntimeError.missingProjector(mmprojURL)
            }
        }
        guard fileManager.fileExists(atPath: executableURL.path), fileManager.isExecutableFile(atPath: executableURL.path) else {
            state = .failed(RuntimeError.statusMessage(for: RuntimeError.missingExecutable(executableURL)))
            throw RuntimeError.missingExecutable(executableURL)
        }

        let discoveredHelpers = verifiedStillLoopHelpers()
        if !discoveredHelpers.isEmpty {
            if discoveredHelpers.count == 1, await canReuseExistingService(baseURL: baseURL) {
                adoptRunningService(baseURL: baseURL)
                return
            }
            terminateVerifiedHelpers(discoveredHelpers)
            guard await waitForVerifiedHelpersToExit() else {
                let error = RuntimeError.launchFailed("existing stillloop-llama-server helpers did not exit")
                state = .failed(RuntimeError.statusMessage(for: error))
                throw error
            }
        }

        try removeStaleSocketFile()
        try await launchRuntime(baseURL: baseURL)
    }

    private func canReuseExistingService(baseURL: URL) async -> Bool {
        do {
            _ = try await readinessProbe(baseURL, spec.localServerModelID)
            return true
        } catch {
            return false
        }
    }

    private func adoptRunningService(baseURL: URL) {
        process = nil
        self.baseURL = baseURL
        state = .running
    }

    private func launchRuntime(baseURL: URL) async throws {
        state = .starting
        self.baseURL = baseURL
        do {
            let launchedProcess = try processLauncher.launch(
                executableURL: executableURL,
                arguments: Self.launchArguments(modelURL: modelURL, mmprojURL: mmprojURL, spec: spec, socketURL: socketURL)
            )
            process = launchedProcess
            _ = try await waitUntilReady(baseURL: baseURL)
            state = .running
        } catch {
            _ = await stopOwnedProcess()
            let message = RuntimeError.statusMessage(for: error)
            state = .failed(message)
            if let runtimeError = error as? RuntimeError {
                throw runtimeError
            }
            throw RuntimeError.readinessFailed(String(describing: error))
        }
    }

    private func waitForVerifiedHelpersToExit() async -> Bool {
        for _ in 0..<max(1, processExitMaxAttempts) {
            guard verifiedStillLoopHelpers().isEmpty else {
                try? await Task.sleep(nanoseconds: processExitRetryDelayNanoseconds)
                continue
            }
            return true
        }
        return verifiedStillLoopHelpers().isEmpty
    }

    private func terminateVerifiedHelpers(_ helpers: [VerifiedStillLoopHelper]) {
        var terminatedPIDs = Set<Int32>()
        for helper in helpers where terminatedPIDs.insert(helper.occupant.pid).inserted {
            terminatePortOccupant(helper.occupant)
        }
    }

    @discardableResult
    private func stopOwnedProcess() async -> Bool {
        guard let process else { return true }
        process.terminate()
        for _ in 0..<max(0, processExitMaxAttempts) {
            guard process.isRunning else { break }
            try? await Task.sleep(nanoseconds: processExitRetryDelayNanoseconds)
        }
        guard !process.isRunning else {
            state = .running
            return false
        }
        self.process = nil
        state = .stopped
        return true
    }

    private func removeStaleSocketFile() throws {
        guard fileManager.fileExists(atPath: socketURL.path) else { return }
        try fileManager.removeItem(at: socketURL)
    }

    private func restartForMemoryPressureIfNeeded() async {
        guard
            let process,
            process.isRunning,
            let bytes = residentMemoryBytes(process.processIdentifier),
            bytes > maximumResidentMemoryBytes
        else {
            return
        }

        process.terminate()
        for _ in 0..<max(0, processExitMaxAttempts) {
            guard process.isRunning else { break }
            try? await Task.sleep(nanoseconds: processExitRetryDelayNanoseconds)
        }
        if !process.isRunning {
            self.process = nil
            state = .stopped
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        terminateVerifiedHelpers(verifiedStillLoopHelpers())
        state = .stopped
    }

    deinit {
        stop()
    }

    private func waitUntilReady(baseURL: URL) async throws -> Readiness {
        let attempts = max(1, readinessMaxAttempts)
        var lastError: Error?

        for attempt in 1...attempts {
            do {
                return try await readinessProbe(baseURL, spec.localServerModelID)
            } catch RuntimeError.imageInputUnavailable {
                throw RuntimeError.imageInputUnavailable
            } catch {
                lastError = error
                if attempt < attempts {
                    try await Task.sleep(nanoseconds: readinessRetryDelayNanoseconds)
                }
            }
        }

        if let runtimeError = lastError as? RuntimeError {
            throw runtimeError
        }
        throw RuntimeError.readinessFailed(String(describing: lastError ?? URLError(.timedOut)))
    }

    private static func defaultReadinessProbe(baseURL: URL, modelID: String) async throws -> Readiness {
        let engine = OpenAICompatibleLLMEngine(baseURL: baseURL, model: modelID, disablesReasoning: true)
        do {
            _ = try await engine.checkModelReadiness(requiresImageInput: true)
            return .ready
        } catch OpenAICompatibleLLMEngine.ReadinessError.imageInputUnavailable {
            throw RuntimeError.imageInputUnavailable
        } catch {
            throw RuntimeError.readinessFailed(String(describing: error))
        }
    }

    private struct VerifiedStillLoopHelper {
        var occupant: BundledModelPortOccupant
        var socketURL: URL
    }

    private func verifiedStillLoopHelpers() -> [VerifiedStillLoopHelper] {
        helperProcesses()
            .compactMap { occupant -> VerifiedStillLoopHelper? in
                guard let helperSocketURL = verifiedStillLoopHelperSocketURL(for: occupant) else { return nil }
                return VerifiedStillLoopHelper(occupant: occupant, socketURL: helperSocketURL)
            }
    }

    private func verifiedStillLoopHelperSocketURL(for occupant: BundledModelPortOccupant) -> URL? {
        let occupantURL = URL(fileURLWithPath: occupant.executablePath).standardizedFileURL
        let expectedURL = executableURL.standardizedFileURL
        guard isCurrentOrLegacyHelperExecutable(occupantURL, expectedURL: expectedURL) else { return nil }
        guard
            let socketPath = argumentValue(in: occupant.arguments, flag: "--host"),
            socketPath == socketURL.path
        else {
            return nil
        }
        guard argumentValue(in: occupant.arguments, flag: "-m") == modelURL.path
            || argumentValue(in: occupant.arguments, flag: "--model") == modelURL.path
        else {
            return nil
        }
        if let mmprojURL {
            guard argumentValue(in: occupant.arguments, flag: "--mmproj") == mmprojURL.path else {
                return nil
            }
        }
        return socketURL
    }

    private func isCurrentOrLegacyHelperExecutable(_ occupantURL: URL, expectedURL: URL) -> Bool {
        if occupantURL.path == expectedURL.path, occupantURL.lastPathComponent == Self.helperExecutableName {
            return true
        }
        return occupantURL.lastPathComponent == Self.legacyHelperExecutableName
            && occupantURL.deletingLastPathComponent().path == expectedURL.deletingLastPathComponent().path
    }

    private func argumentValue(in arguments: [String], flag: String) -> String? {
        for index in arguments.indices {
            if arguments[index] == flag, arguments.indices.contains(index + 1) {
                return arguments[index + 1]
            }
            let prefix = "\(flag)="
            if arguments[index].hasPrefix(prefix) {
                return String(arguments[index].dropFirst(prefix.count))
            }
        }
        return nil
    }

    private static func runningProcesses() -> [BundledModelPortOccupant] {
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return [] }
        let count = Int(bytes) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: count)
        let writtenBytes = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, bytes)
        }
        guard writtenBytes > 0 else { return [] }
        return pids.compactMap { pid in
            guard pid > 0,
                  let executablePath = processPath(pid: pid),
                  let arguments = processArguments(pid: pid)
            else {
                return nil
            }
            return BundledModelPortOccupant(pid: pid, executablePath: executablePath, arguments: arguments)
        }
    }

    private static func processPath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func processArguments(pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 {
            index += 1
        }
        while index < size, buffer[index] == 0 {
            index += 1
        }
        var arguments: [String] = []
        for _ in 0..<argc {
            let start = index
            while index < size, buffer[index] != 0 {
                index += 1
            }
            if index > start, let argument = String(bytes: buffer[start..<index], encoding: .utf8) {
                arguments.append(argument)
            }
            while index < size, buffer[index] == 0 {
                index += 1
            }
        }
        return arguments
    }

    private static func defaultTerminatePortOccupant(_ occupant: BundledModelPortOccupant) {
        kill(occupant.pid, SIGTERM)
    }

    private static let defaultMaximumResidentMemoryBytes: UInt64 = 2_500 * 1024 * 1024
    private static let helperExecutableName = "stillloop-llama-server"
    private static let legacyHelperExecutableName = "llama-server"
    private static let helperExecutableNames: Set<String> = [helperExecutableName, legacyHelperExecutableName]

    private static func defaultSocketURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("sl-\(getpid()).sock")
    }

    private static func residentMemoryBytes(for processIdentifier: Int32) -> UInt64? {
        var taskInfo = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = withUnsafeMutablePointer(to: &taskInfo) { pointer in
            proc_pidinfo(processIdentifier, PROC_PIDTASKINFO, 0, pointer, size)
        }
        guard result == size else { return nil }
        return taskInfo.pti_resident_size
    }
}

struct FoundationBundledModelProcessLauncher: BundledModelProcessLaunching {
    private let parentProcessIdentifier: Int32

    init(parentProcessIdentifier: Int32 = getpid()) {
        self.parentProcessIdentifier = parentProcessIdentifier
    }

    func launch(executableURL: URL, arguments: [String]) throws -> BundledModelProcessManaging {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputDrain = BoundedProcessPipeDrain(pipe: outputPipe)
        let errorDrain = BoundedProcessPipeDrain(pipe: errorPipe)
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            try process.run()
            let parentMonitor = ParentProcessDeathMonitor.launch(
                parentProcessIdentifier: parentProcessIdentifier,
                childProcessIdentifier: process.processIdentifier
            )
            return FoundationBundledModelProcess(process: process, drains: [outputDrain, errorDrain], parentMonitor: parentMonitor)
        } catch {
            outputDrain.close()
            errorDrain.close()
            throw BundledModelRuntime.RuntimeError.launchFailed(String(describing: error))
        }
    }
}

private final class FoundationBundledModelProcess: BundledModelProcessManaging {
    private let process: Process
    private let drains: [BoundedProcessPipeDrain]
    private let parentMonitor: ParentProcessDeathMonitor?

    init(process: Process, drains: [BoundedProcessPipeDrain], parentMonitor: ParentProcessDeathMonitor?) {
        self.process = process
        self.drains = drains
        self.parentMonitor = parentMonitor
        process.terminationHandler = { _ in
            drains.forEach { $0.close() }
            parentMonitor?.stop()
        }
    }

    var isRunning: Bool {
        process.isRunning
    }

    var processIdentifier: Int32 {
        process.processIdentifier
    }

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }

    deinit {
        drains.forEach { $0.close() }
        parentMonitor?.stop()
    }
}

private final class ParentProcessDeathMonitor {
    private let process: Process

    private init(process: Process) {
        self.process = process
    }

    static func launch(parentProcessIdentifier: Int32, childProcessIdentifier: Int32) -> ParentProcessDeathMonitor? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            """
            parent="$1"
            child="$2"
            while kill -0 "$child" 2>/dev/null; do
              if ! kill -0 "$parent" 2>/dev/null; then
                kill -TERM "$child" 2>/dev/null
                sleep 2
                kill -KILL "$child" 2>/dev/null
                exit 0
              fi
              sleep 1
            done
            """,
            "stillloop-parent-monitor",
            String(parentProcessIdentifier),
            String(childProcessIdentifier)
        ]
        do {
            try process.run()
            return ParentProcessDeathMonitor(process: process)
        } catch {
            return nil
        }
    }

    func stop() {
        guard process.isRunning else { return }
        process.terminate()
    }
}

private final class BoundedProcessPipeDrain {
    private let fileHandle: FileHandle
    private let maxTailBytes: Int
    private let lock = NSLock()
    private var tail = Data()

    init(pipe: Pipe, maxTailBytes: Int = 8_192) {
        self.fileHandle = pipe.fileHandleForReading
        self.maxTailBytes = maxTailBytes
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                self?.close()
                return
            }
            self?.append(data)
        }
    }

    func close() {
        fileHandle.readabilityHandler = nil
    }

    private func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        tail.append(data)
        if tail.count > maxTailBytes {
            tail.removeFirst(tail.count - maxTailBytes)
        }
    }

    var diagnosticTail: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: tail, as: UTF8.self)
    }
}
