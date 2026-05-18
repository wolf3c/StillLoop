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
    var processIdentifier: Int32 { get }
    func terminate()
}

protocol BundledModelProcessLaunching {
    func launch(executableURL: URL, arguments: [String]) throws -> BundledModelProcessManaging
}

struct BundledModelPortOccupant: Equatable {
    var pid: Int32
    var executablePath: String
    var arguments: [String]
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
        case missingProjector(URL)
        case portInUse(Int)
        case noAvailablePort(ClosedRange<Int>)
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
            case .portInUse:
                return "端口被占用"
            case .noAvailablePort:
                return "可用端口不足"
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

    let modelID: String
    private(set) var activePort: Int
    private(set) var baseURL: URL
    private(set) var state: State = .notStarted

    private let executableURL: URL
    private let modelURL: URL
    private let mmprojURL: URL?
    private let spec: ModelDownloadSpec
    private let fileManager: FileManager
    private let processLauncher: BundledModelProcessLaunching
    private let isPortInUse: (Int) -> Bool
    private let portOccupant: (Int) -> BundledModelPortOccupant?
    private let terminatePortOccupant: (BundledModelPortOccupant) -> Void
    private let readinessProbe: (URL, String) async throws -> Readiness
    private let candidatePorts: ClosedRange<Int>
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
        spec: ModelDownloadSpec,
        fileManager: FileManager = .default,
        processLauncher: BundledModelProcessLaunching = FoundationBundledModelProcessLauncher(),
        isPortInUse: @escaping (Int) -> Bool = BundledModelRuntime.isTCPPortInUse,
        portOccupant: @escaping (Int) -> BundledModelPortOccupant? = BundledModelRuntime.defaultPortOccupant,
        terminatePortOccupant: @escaping (BundledModelPortOccupant) -> Void = BundledModelRuntime.defaultTerminatePortOccupant,
        readinessProbe: @escaping (URL, String) async throws -> Readiness = BundledModelRuntime.defaultReadinessProbe,
        candidatePorts: ClosedRange<Int>? = nil,
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
        self.spec = spec
        self.fileManager = fileManager
        self.processLauncher = processLauncher
        self.isPortInUse = isPortInUse
        self.portOccupant = portOccupant
        self.terminatePortOccupant = terminatePortOccupant
        self.readinessProbe = readinessProbe
        self.candidatePorts = candidatePorts ?? spec.localServerPort...(spec.localServerPort + 9)
        self.readinessMaxAttempts = readinessMaxAttempts
        self.readinessRetryDelayNanoseconds = readinessRetryDelayNanoseconds
        self.maximumResidentMemoryBytes = maximumResidentMemoryBytes
        self.residentMemoryBytes = residentMemoryBytes
        self.processExitMaxAttempts = processExitMaxAttempts
        self.processExitRetryDelayNanoseconds = processExitRetryDelayNanoseconds
        activePort = spec.localServerPort
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
        port: Int? = nil
    ) -> [String] {
        let selectedPort = port ?? spec.localServerPort
        var arguments = [
            "-m", modelURL.path,
            "--host", "127.0.0.1",
            "--port", String(selectedPort),
            "--ctx-size", String(spec.recommendedContextSize),
            "--parallel", "1",
            "--n-gpu-layers", "99",
            "--cache-type-k", spec.recommendedCacheTypeK,
            "--cache-type-v", spec.recommendedCacheTypeV,
            "--no-cache-prompt",
            "--cache-ram", "0"
        ]
        if let mmprojURL {
            arguments.insert(contentsOf: ["--mmproj", mmprojURL.path], at: 2)
        }
        return arguments
    }

    func startIfNeeded() async throws {
        await restartForMemoryPressureIfNeeded()

        if let process, process.isRunning {
            if isPortInUse(activePort) {
                state = .running
                return
            }
            await stopOwnedProcess()
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

        for port in candidatePorts {
            let candidateBaseURL = spec.localServerBaseURL(port: port)
            if isPortInUse(port) {
                if await canReuseExistingService(baseURL: candidateBaseURL) {
                    adoptRunningService(port: port, baseURL: candidateBaseURL)
                    return
                }
                if let occupant = portOccupant(port), isStillLoopHelper(occupant, port: port) {
                    terminatePortOccupant(occupant)
                    await waitForPortRelease(port)
                    if !isPortInUse(port) {
                        try await launchRuntime(port: port, baseURL: candidateBaseURL)
                        return
                    }
                }
                continue
            }

            try await launchRuntime(port: port, baseURL: candidateBaseURL)
            return
        }

        state = .failed(RuntimeError.statusMessage(for: RuntimeError.noAvailablePort(candidatePorts)))
        throw RuntimeError.noAvailablePort(candidatePorts)
    }

    private func canReuseExistingService(baseURL: URL) async -> Bool {
        do {
            _ = try await readinessProbe(baseURL, spec.localServerModelID)
            return true
        } catch {
            return false
        }
    }

    private func adoptRunningService(port: Int, baseURL: URL) {
        process = nil
        activePort = port
        self.baseURL = baseURL
        state = .running
    }

    private func launchRuntime(port: Int, baseURL: URL) async throws {
        state = .starting
        activePort = port
        self.baseURL = baseURL
        do {
            let launchedProcess = try processLauncher.launch(
                executableURL: executableURL,
                arguments: Self.launchArguments(modelURL: modelURL, mmprojURL: mmprojURL, spec: spec, port: port)
            )
            process = launchedProcess
            _ = try await waitUntilReady(baseURL: baseURL)
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

    private func waitForPortRelease(_ port: Int) async {
        for _ in 0..<max(1, processExitMaxAttempts) {
            guard isPortInUse(port) else { return }
            try? await Task.sleep(nanoseconds: processExitRetryDelayNanoseconds)
        }
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

    private func stopOwnedProcess() async {
        guard let process else { return }
        process.terminate()
        for _ in 0..<max(0, processExitMaxAttempts) {
            guard process.isRunning else { break }
            try? await Task.sleep(nanoseconds: processExitRetryDelayNanoseconds)
        }
        self.process = nil
        state = .stopped
    }

    func stop() {
        process?.terminate()
        process = nil
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

    private func isStillLoopHelper(_ occupant: BundledModelPortOccupant, port: Int) -> Bool {
        let occupantURL = URL(fileURLWithPath: occupant.executablePath).standardizedFileURL
        let expectedURL = executableURL.standardizedFileURL
        guard isCurrentOrLegacyHelperExecutable(occupantURL, expectedURL: expectedURL) else { return false }
        guard arguments(occupant.arguments, containFlag: "--host", value: "127.0.0.1") else { return false }
        guard arguments(occupant.arguments, containFlag: "--port", value: String(port)) else { return false }
        guard occupant.arguments.contains(modelURL.path) else { return false }
        if let mmprojURL, !occupant.arguments.contains(mmprojURL.path) {
            return false
        }
        return true
    }

    private func isCurrentOrLegacyHelperExecutable(_ occupantURL: URL, expectedURL: URL) -> Bool {
        if occupantURL.path == expectedURL.path, occupantURL.lastPathComponent == Self.helperExecutableName {
            return true
        }
        return occupantURL.lastPathComponent == Self.legacyHelperExecutableName
            && occupantURL.deletingLastPathComponent().path == expectedURL.deletingLastPathComponent().path
    }

    private func arguments(_ arguments: [String], containFlag flag: String, value: String) -> Bool {
        arguments.indices.contains { index in
            arguments[index] == flag
                && arguments.indices.contains(index + 1)
                && arguments[index + 1] == value
        }
    }

    private static func defaultPortOccupant(port: Int) -> BundledModelPortOccupant? {
        runningProcesses().first { process in
            Self.helperExecutableNames.contains(URL(fileURLWithPath: process.executablePath).lastPathComponent)
                && process.argumentsContain(flag: "--host", value: "127.0.0.1")
                && process.argumentsContain(flag: "--port", value: String(port))
        }
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
            return FoundationBundledModelProcess(process: process, drains: [outputDrain, errorDrain])
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

    init(process: Process, drains: [BoundedProcessPipeDrain]) {
        self.process = process
        self.drains = drains
        process.terminationHandler = { _ in
            drains.forEach { $0.close() }
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

private extension BundledModelPortOccupant {
    func argumentsContain(flag: String, value: String) -> Bool {
        arguments.indices.contains { index in
            arguments[index] == flag
                && arguments.indices.contains(index + 1)
                && arguments[index + 1] == value
        }
    }
}
