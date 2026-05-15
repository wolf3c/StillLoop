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

protocol BundledModelProcessManaging: AnyObject {
    var isRunning: Bool { get }
    func terminate()
}

protocol BundledModelProcessLaunching {
    func launch(executableURL: URL, arguments: [String]) throws -> BundledModelProcessManaging
}

final class BundledModelRuntime: BundledModelRuntimeManaging {
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
        case portInUse(Int)
        case launchFailed(String)
        case imageInputUnavailable
        case readinessFailed(String)

        static func statusMessage(for error: Error) -> String {
            guard let runtimeError = error as? RuntimeError else {
                return "启动失败"
            }
            switch runtimeError {
            case .missingExecutable:
                return "缺少 llama-server"
            case .missingModel:
                return "缺少模型文件"
            case .portInUse:
                return "端口被占用"
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

    let baseURL: URL
    let modelID: String
    private(set) var state: State = .notStarted

    private let executableURL: URL
    private let modelURL: URL
    private let spec: ModelDownloadSpec
    private let fileManager: FileManager
    private let processLauncher: BundledModelProcessLaunching
    private let isPortInUse: (Int) -> Bool
    private let readinessProbe: (URL, String) async throws -> Readiness
    private let readinessMaxAttempts: Int
    private let readinessRetryDelayNanoseconds: UInt64
    private var process: BundledModelProcessManaging?

    init(
        executableURL: URL,
        modelURL: URL,
        spec: ModelDownloadSpec,
        fileManager: FileManager = .default,
        processLauncher: BundledModelProcessLaunching = FoundationBundledModelProcessLauncher(),
        isPortInUse: @escaping (Int) -> Bool = BundledModelRuntime.isTCPPortInUse,
        readinessProbe: @escaping (URL, String) async throws -> Readiness = BundledModelRuntime.defaultReadinessProbe,
        readinessMaxAttempts: Int = 60,
        readinessRetryDelayNanoseconds: UInt64 = 500_000_000
    ) {
        self.executableURL = executableURL
        self.modelURL = modelURL
        self.spec = spec
        self.fileManager = fileManager
        self.processLauncher = processLauncher
        self.isPortInUse = isPortInUse
        self.readinessProbe = readinessProbe
        self.readinessMaxAttempts = readinessMaxAttempts
        self.readinessRetryDelayNanoseconds = readinessRetryDelayNanoseconds
        baseURL = spec.localServerBaseURL
        modelID = spec.localServerModelID
    }

    static func defaultRuntime(
        modelURL: URL,
        bundle: Bundle = .main
    ) -> BundledModelRuntime {
        BundledModelRuntime(
            executableURL: bundledLlamaServerURL(bundle: bundle),
            modelURL: modelURL,
            spec: .builtIn
        )
    }

    static func bundledLlamaServerURL(bundle: Bundle = .main) -> URL {
        if bundle.bundleURL.pathExtension == "app" {
            return bundle.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent("llama-server")
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

    static func launchArguments(modelURL: URL, spec: ModelDownloadSpec) -> [String] {
        [
            "-m", modelURL.path,
            "--host", "127.0.0.1",
            "--port", String(spec.localServerPort),
            "--ctx-size", String(spec.recommendedContextSize),
            "--parallel", "1",
            "--n-gpu-layers", "99",
            "--cache-type-k", spec.recommendedCacheTypeK,
            "--cache-type-v", spec.recommendedCacheTypeV
        ]
    }

    func startIfNeeded() async throws {
        if process?.isRunning == true {
            state = .running
            return
        }

        guard fileManager.fileExists(atPath: modelURL.path) else {
            state = .failed(RuntimeError.statusMessage(for: RuntimeError.missingModel(modelURL)))
            throw RuntimeError.missingModel(modelURL)
        }
        guard fileManager.fileExists(atPath: executableURL.path), fileManager.isExecutableFile(atPath: executableURL.path) else {
            state = .failed(RuntimeError.statusMessage(for: RuntimeError.missingExecutable(executableURL)))
            throw RuntimeError.missingExecutable(executableURL)
        }
        guard !isPortInUse(spec.localServerPort) else {
            state = .failed(RuntimeError.statusMessage(for: RuntimeError.portInUse(spec.localServerPort)))
            throw RuntimeError.portInUse(spec.localServerPort)
        }

        state = .starting
        do {
            let launchedProcess = try processLauncher.launch(
                executableURL: executableURL,
                arguments: Self.launchArguments(modelURL: modelURL, spec: spec)
            )
            process = launchedProcess
            _ = try await waitUntilReady()
            state = .running
        } catch {
            process?.terminate()
            process = nil
            let message = RuntimeError.statusMessage(for: error)
            state = .failed(message)
            if let runtimeError = error as? RuntimeError {
                throw runtimeError
            }
            throw RuntimeError.readinessFailed(String(describing: error))
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

    private func waitUntilReady() async throws -> Readiness {
        let attempts = max(1, readinessMaxAttempts)
        var lastError: Error?

        for attempt in 1...attempts {
            do {
                return try await readinessProbe(spec.localServerBaseURL, spec.localServerModelID)
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
        let engine = OpenAICompatibleLLMEngine(baseURL: baseURL, model: modelID)
        do {
            _ = try await engine.checkModelReadiness(requiresImageInput: true)
            return .ready
        } catch OpenAICompatibleLLMEngine.ReadinessError.imageInputUnavailable {
            throw RuntimeError.imageInputUnavailable
        } catch {
            throw RuntimeError.readinessFailed(String(describing: error))
        }
    }

    private static func isTCPPortInUse(_ port: Int) -> Bool {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { return false }
        defer { close(socketDescriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPointer in
                connect(socketDescriptor, reboundPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}

struct FoundationBundledModelProcessLauncher: BundledModelProcessLaunching {
    func launch(executableURL: URL, arguments: [String]) throws -> BundledModelProcessManaging {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            return FoundationBundledModelProcess(process: process)
        } catch {
            throw BundledModelRuntime.RuntimeError.launchFailed(String(describing: error))
        }
    }
}

private final class FoundationBundledModelProcess: BundledModelProcessManaging {
    private let process: Process

    init(process: Process) {
        self.process = process
    }

    var isRunning: Bool {
        process.isRunning
    }

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }
}
