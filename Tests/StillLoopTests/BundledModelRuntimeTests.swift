import Foundation
import XCTest
@testable import StillLoop
import StillLoopCore

final class BundledModelRuntimeTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StillLoopRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testLaunchArgumentsUseDedicatedLlamaServerSettings() {
        let modelURL = URL(fileURLWithPath: "/tmp/StillLoop Models/model.gguf")
        let mmprojURL = URL(fileURLWithPath: "/tmp/StillLoop Models/mmproj.gguf")

        let arguments = BundledModelRuntime.launchArguments(
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            spec: .builtIn
        )

        XCTAssertEqual(arguments, [
            "-m", "/tmp/StillLoop Models/model.gguf",
            "--mmproj", "/tmp/StillLoop Models/mmproj.gguf",
            "--host", "127.0.0.1",
            "--port", "17631",
            "--ctx-size", "32768",
            "--parallel", "1",
            "--n-gpu-layers", "99",
            "--cache-type-k", "f16",
            "--cache-type-v", "f16",
            "--no-cache-prompt",
            "--cache-ram", "0"
        ])
    }

    func testLaunchArgumentsUseSelectedPort() {
        let modelURL = URL(fileURLWithPath: "/tmp/model.gguf")

        let arguments = BundledModelRuntime.launchArguments(
            modelURL: modelURL,
            mmprojURL: nil,
            spec: .builtIn,
            port: 17_632
        )

        XCTAssertEqual(arguments[arguments.firstIndex(of: "--port")! + 1], "17632")
    }

    func testStartFailsWhenProjectorFileIsMissingWithoutLaunchingProcess() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = temporaryDirectory.appendingPathComponent("missing-mmproj.gguf")
        let launcher = FakeBundledModelProcessLauncher()
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            spec: .builtIn,
            processLauncher: launcher,
            isPortInUse: { _ in false },
            readinessProbe: { _, _ in .ready }
        )

        do {
            try await runtime.startIfNeeded()
            XCTFail("Expected missing projector file to prevent runtime launch")
        } catch let error as BundledModelRuntime.RuntimeError {
            XCTAssertEqual(error, .missingProjector(mmprojURL))
            XCTAssertEqual(launcher.launchCount, 0)
        }
    }

    func testStartFailsWhenModelFileIsMissingWithoutLaunchingProcess() async throws {
        let executableURL = try makeExecutable()
        let modelURL = temporaryDirectory.appendingPathComponent("missing.gguf")
        let launcher = FakeBundledModelProcessLauncher()
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: nil,
            spec: .builtIn,
            processLauncher: launcher,
            isPortInUse: { _ in false },
            readinessProbe: { _, _ in .ready }
        )

        do {
            try await runtime.startIfNeeded()
            XCTFail("Expected missing model file to prevent runtime launch")
        } catch let error as BundledModelRuntime.RuntimeError {
            XCTAssertEqual(error, .missingModel(modelURL))
            XCTAssertEqual(launcher.launchCount, 0)
        }
    }

    func testStartReusesHealthyCompatibleServiceOnDefaultPort() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = try makeProjectorFile()
        let launcher = FakeBundledModelProcessLauncher()
        var probedBaseURLs: [URL] = []
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            spec: .builtIn,
            processLauncher: launcher,
            isPortInUse: { $0 == ModelDownloadSpec.builtIn.localServerPort },
            portOccupant: { _ in
                XCTFail("Healthy service reuse should not need process ownership checks")
                return nil
            },
            readinessProbe: { baseURL, _ in
                probedBaseURLs.append(baseURL)
                return .ready
            }
        )

        try await runtime.startIfNeeded()

        XCTAssertEqual(launcher.launchCount, 0)
        XCTAssertEqual(probedBaseURLs, [ModelDownloadSpec.builtIn.localServerBaseURL])
        XCTAssertEqual(runtime.baseURL, ModelDownloadSpec.builtIn.localServerBaseURL)
        XCTAssertEqual(runtime.state, .running)
    }

    func testStartTerminatesStaleStillLoopHelperOnDefaultPortThenRestarts() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = try makeProjectorFile()
        let launcher = FakeBundledModelProcessLauncher()
        var occupiedPorts: Set<Int> = [ModelDownloadSpec.builtIn.localServerPort]
        let staleHelper = BundledModelPortOccupant(
            pid: 42,
            executablePath: executableURL.path,
            arguments: [
                executableURL.path,
                "-m", modelURL.path,
                "--mmproj", mmprojURL.path,
                "--host", "127.0.0.1",
                "--port", "17631"
            ]
        )
        var terminatedOccupants: [BundledModelPortOccupant] = []
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            spec: .builtIn,
            processLauncher: launcher,
            isPortInUse: { occupiedPorts.contains($0) },
            portOccupant: { port in
                port == ModelDownloadSpec.builtIn.localServerPort ? staleHelper : nil
            },
            terminatePortOccupant: { occupant in
                terminatedOccupants.append(occupant)
                occupiedPorts.remove(ModelDownloadSpec.builtIn.localServerPort)
            },
            readinessProbe: { baseURL, _ in
                if baseURL == ModelDownloadSpec.builtIn.localServerBaseURL, occupiedPorts.contains(ModelDownloadSpec.builtIn.localServerPort) {
                    throw URLError(.cannotConnectToHost)
                }
                return .ready
            }
        )

        try await runtime.startIfNeeded()

        XCTAssertEqual(terminatedOccupants, [staleHelper])
        XCTAssertEqual(launcher.launchCount, 1)
        XCTAssertEqual(
            launcher.lastArguments,
            BundledModelRuntime.launchArguments(modelURL: modelURL, mmprojURL: mmprojURL, spec: .builtIn)
        )
        XCTAssertEqual(runtime.baseURL, ModelDownloadSpec.builtIn.localServerBaseURL)
    }

    func testStartTerminatesLegacyStillLoopHelperOnDefaultPortThenRestarts() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = try makeProjectorFile()
        let launcher = FakeBundledModelProcessLauncher()
        var occupiedPorts: Set<Int> = [ModelDownloadSpec.builtIn.localServerPort]
        let legacyExecutableURL = executableURL.deletingLastPathComponent().appendingPathComponent("llama-server")
        let staleHelper = BundledModelPortOccupant(
            pid: 43,
            executablePath: legacyExecutableURL.path,
            arguments: [
                legacyExecutableURL.path,
                "-m", modelURL.path,
                "--mmproj", mmprojURL.path,
                "--host", "127.0.0.1",
                "--port", "17631"
            ]
        )
        var terminatedOccupants: [BundledModelPortOccupant] = []
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            spec: .builtIn,
            processLauncher: launcher,
            isPortInUse: { occupiedPorts.contains($0) },
            portOccupant: { port in
                port == ModelDownloadSpec.builtIn.localServerPort ? staleHelper : nil
            },
            terminatePortOccupant: { occupant in
                terminatedOccupants.append(occupant)
                occupiedPorts.remove(ModelDownloadSpec.builtIn.localServerPort)
            },
            readinessProbe: { baseURL, _ in
                if baseURL == ModelDownloadSpec.builtIn.localServerBaseURL, occupiedPorts.contains(ModelDownloadSpec.builtIn.localServerPort) {
                    throw URLError(.cannotConnectToHost)
                }
                return .ready
            }
        )

        try await runtime.startIfNeeded()

        XCTAssertEqual(terminatedOccupants, [staleHelper])
        XCTAssertEqual(launcher.launchCount, 1)
        XCTAssertEqual(runtime.baseURL, ModelDownloadSpec.builtIn.localServerBaseURL)
    }

    func testStartUsesNextPortWhenDefaultPortBelongsToAnotherProcess() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = try makeProjectorFile()
        let launcher = FakeBundledModelProcessLauncher()
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            spec: .builtIn,
            processLauncher: launcher,
            isPortInUse: { $0 == ModelDownloadSpec.builtIn.localServerPort },
            portOccupant: { port in
                BundledModelPortOccupant(
                    pid: Int32(port),
                    executablePath: "/usr/bin/other-server",
                    arguments: ["/usr/bin/other-server", "--port", "\(port)"]
                )
            },
            terminatePortOccupant: { _ in
                XCTFail("Other processes must not be terminated")
            },
            readinessProbe: { baseURL, _ in
                if baseURL == ModelDownloadSpec.builtIn.localServerBaseURL {
                    throw URLError(.cannotConnectToHost)
                }
                return .ready
            }
        )

        try await runtime.startIfNeeded()

        XCTAssertEqual(launcher.launchCount, 1)
        XCTAssertEqual(
            launcher.lastArguments,
            BundledModelRuntime.launchArguments(modelURL: modelURL, mmprojURL: mmprojURL, spec: .builtIn, port: 17_632)
        )
        XCTAssertEqual(runtime.baseURL, ModelDownloadSpec.builtIn.localServerBaseURL(port: 17_632))
    }

    func testStartSkipsMultipleOccupiedPortsAndUsesFirstAvailablePort() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = try makeProjectorFile()
        let launcher = FakeBundledModelProcessLauncher()
        let occupiedPorts: Set<Int> = [17_631, 17_632]
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            spec: .builtIn,
            processLauncher: launcher,
            isPortInUse: { occupiedPorts.contains($0) },
            portOccupant: { _ in nil },
            readinessProbe: { baseURL, _ in
                if baseURL == ModelDownloadSpec.builtIn.localServerBaseURL
                    || baseURL == ModelDownloadSpec.builtIn.localServerBaseURL(port: 17_632) {
                    throw URLError(.cannotConnectToHost)
                }
                return .ready
            },
            candidatePorts: 17_631...17_633
        )

        try await runtime.startIfNeeded()

        XCTAssertEqual(launcher.launchCount, 1)
        XCTAssertEqual(
            launcher.lastArguments,
            BundledModelRuntime.launchArguments(modelURL: modelURL, mmprojURL: mmprojURL, spec: .builtIn, port: 17_633)
        )
        XCTAssertEqual(runtime.baseURL, ModelDownloadSpec.builtIn.localServerBaseURL(port: 17_633))
    }

    func testStartReportsNoAvailablePortWhenCandidatePortsAreUnavailable() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = try makeProjectorFile()
        let launcher = FakeBundledModelProcessLauncher()
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            spec: .builtIn,
            processLauncher: launcher,
            isPortInUse: { _ in true },
            portOccupant: { _ in nil },
            readinessProbe: { _, _ in throw URLError(.cannotConnectToHost) },
            candidatePorts: 17_631...17_632
        )

        do {
            try await runtime.startIfNeeded()
            XCTFail("Expected no available model runtime port")
        } catch let error as BundledModelRuntime.RuntimeError {
            XCTAssertEqual(error, .noAvailablePort(17_631...17_632))
            XCTAssertEqual(launcher.launchCount, 0)
            XCTAssertEqual(runtime.state, .failed("可用端口不足"))
        }
    }

    func testStartLaunchesProcessAndRequiresImageReadiness() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = try makeProjectorFile()
        let launcher = FakeBundledModelProcessLauncher()
        var probedBaseURL: URL?
        var probedModelID: String?
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            spec: .builtIn,
            processLauncher: launcher,
            isPortInUse: { _ in false },
            readinessProbe: { baseURL, modelID in
                probedBaseURL = baseURL
                probedModelID = modelID
                return .ready
            }
        )

        try await runtime.startIfNeeded()

        XCTAssertEqual(launcher.launchCount, 1)
        XCTAssertEqual(launcher.lastExecutableURL, executableURL)
        XCTAssertEqual(
            launcher.lastArguments,
            BundledModelRuntime.launchArguments(modelURL: modelURL, mmprojURL: mmprojURL, spec: .builtIn)
        )
        XCTAssertEqual(probedBaseURL, ModelDownloadSpec.builtIn.localServerBaseURL)
        XCTAssertEqual(probedModelID, ModelDownloadSpec.builtIn.localServerModelID)
        XCTAssertEqual(runtime.state, .running)
    }

    func testStartRestartsWarmProcessWhenResidentMemoryExceedsLimit() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = try makeProjectorFile()
        let launcher = FakeBundledModelProcessLauncher()
        var residentMemoryByPID: [Int32: UInt64] = [:]
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            spec: .builtIn,
            processLauncher: launcher,
            isPortInUse: { _ in false },
            readinessProbe: { _, _ in .ready },
            maximumResidentMemoryBytes: 1_000,
            residentMemoryBytes: { residentMemoryByPID[$0] },
            processExitRetryDelayNanoseconds: 0
        )

        try await runtime.startIfNeeded()
        let firstProcess = try XCTUnwrap(launcher.launchedProcesses.first)
        residentMemoryByPID[firstProcess.processIdentifier] = 1_001

        try await runtime.startIfNeeded()

        XCTAssertEqual(firstProcess.terminateCount, 1)
        XCTAssertFalse(firstProcess.isRunning)
        XCTAssertEqual(launcher.launchCount, 2)
        XCTAssertEqual(runtime.state, .running)
    }

    func testStartPollsReadinessUntilServerAcceptsImageRequests() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = try makeProjectorFile()
        let launcher = FakeBundledModelProcessLauncher()
        var probeCount = 0
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            spec: .builtIn,
            processLauncher: launcher,
            isPortInUse: { _ in false },
            readinessProbe: { _, _ in
                probeCount += 1
                if probeCount < 3 {
                    throw URLError(.cannotConnectToHost)
                }
                return .ready
            },
            readinessMaxAttempts: 3,
            readinessRetryDelayNanoseconds: 0
        )

        try await runtime.startIfNeeded()

        XCTAssertEqual(probeCount, 3)
        XCTAssertEqual(launcher.launchCount, 1)
        XCTAssertEqual(runtime.state, .running)
    }

    func testStartRestartsRunningProcessWhenActivePortIsUnavailable() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = try makeProjectorFile()
        let launcher = FakeBundledModelProcessLauncher()
        let activePortIsInUse = false
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            spec: .builtIn,
            processLauncher: launcher,
            isPortInUse: { _ in activePortIsInUse },
            readinessProbe: { _, _ in .ready },
            processExitRetryDelayNanoseconds: 0
        )

        try await runtime.startIfNeeded()
        let firstProcess = try XCTUnwrap(launcher.launchedProcesses.first)

        try await runtime.startIfNeeded()

        XCTAssertEqual(firstProcess.terminateCount, 1)
        XCTAssertFalse(firstProcess.isRunning)
        XCTAssertEqual(launcher.launchCount, 2)
        XCTAssertEqual(runtime.state, .running)
    }

    func testFoundationLauncherDrainsHelperOutputPipes() async throws {
        let executableURL = temporaryDirectory.appendingPathComponent("chatty-helper")
        try """
        #!/bin/sh
        i=0
        while [ "$i" -lt 1500 ]; do
          printf 'stdout line %04d abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz\\n' "$i"
          printf 'stderr line %04d abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz\\n' "$i" >&2
          i=$((i + 1))
        done
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let process = try FoundationBundledModelProcessLauncher().launch(executableURL: executableURL, arguments: [])
        for _ in 0..<30 where process.isRunning {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let isStillRunning = process.isRunning
        if isStillRunning {
            process.terminate()
        }

        XCTAssertFalse(isStillRunning, "A helper that writes lots of logs should be drained instead of blocking on a full pipe")
    }

    func testImageReadinessFailureStopsLaunchedProcess() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = try makeProjectorFile()
        let launcher = FakeBundledModelProcessLauncher()
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            spec: .builtIn,
            processLauncher: launcher,
            isPortInUse: { _ in false },
            readinessProbe: { _, _ in
                throw BundledModelRuntime.RuntimeError.imageInputUnavailable
            },
            readinessMaxAttempts: 3,
            readinessRetryDelayNanoseconds: 0
        )

        do {
            try await runtime.startIfNeeded()
            XCTFail("Expected image readiness failure")
        } catch let error as BundledModelRuntime.RuntimeError {
            XCTAssertEqual(error, .imageInputUnavailable)
            XCTAssertEqual(launcher.process.terminateCount, 1)
            XCTAssertEqual(runtime.state, .failed("自带模型不支持图片输入"))
        }
    }

    private func makeExecutable() throws -> URL {
        let url = temporaryDirectory.appendingPathComponent("stillloop-llama-server")
        FileManager.default.createFile(atPath: url.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func makeModelFile() throws -> URL {
        let url = temporaryDirectory.appendingPathComponent("model.gguf")
        FileManager.default.createFile(atPath: url.path, contents: Data("gguf".utf8))
        return url
    }

    private func makeProjectorFile() throws -> URL {
        let url = temporaryDirectory.appendingPathComponent("mmproj.gguf")
        FileManager.default.createFile(atPath: url.path, contents: Data("mmproj".utf8))
        return url
    }
}

private final class FakeBundledModelProcessLauncher: BundledModelProcessLaunching {
    private(set) var launchedProcesses: [FakeBundledModelProcess] = []
    var process: FakeBundledModelProcess {
        launchedProcesses.last ?? FakeBundledModelProcess(processIdentifier: -1)
    }
    private(set) var launchCount = 0
    private(set) var lastExecutableURL: URL?
    private(set) var lastArguments: [String]?

    func launch(executableURL: URL, arguments: [String]) throws -> BundledModelProcessManaging {
        launchCount += 1
        lastExecutableURL = executableURL
        lastArguments = arguments
        let process = FakeBundledModelProcess(processIdentifier: Int32(10_000 + launchCount))
        launchedProcesses.append(process)
        return process
    }
}

private final class FakeBundledModelProcess: BundledModelProcessManaging {
    var isRunning = true
    let processIdentifier: Int32
    private(set) var terminateCount = 0

    init(processIdentifier: Int32) {
        self.processIdentifier = processIdentifier
    }

    func terminate() {
        terminateCount += 1
        isRunning = false
    }
}
