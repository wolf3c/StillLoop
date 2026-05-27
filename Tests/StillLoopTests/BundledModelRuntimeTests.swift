import Darwin
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

    func testLaunchArgumentsUseUnixSocketLlamaServerSettings() {
        let modelURL = URL(fileURLWithPath: "/tmp/StillLoop Models/model.gguf")
        let mmprojURL = URL(fileURLWithPath: "/tmp/StillLoop Models/mmproj.gguf")
        let socketURL = URL(fileURLWithPath: "/tmp/stillloop-runtime.sock")

        let arguments = BundledModelRuntime.launchArguments(
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            spec: .builtIn,
            socketURL: socketURL,
            tuning: .development
        )

        XCTAssertEqual(arguments, [
            "-m", "/tmp/StillLoop Models/model.gguf",
            "--mmproj", "/tmp/StillLoop Models/mmproj.gguf",
            "--host", "/tmp/stillloop-runtime.sock",
            "--ctx-size", "12288",
            "--parallel", "3",
            "--n-gpu-layers", "99",
            "--cache-type-k", "q4_1",
            "--cache-type-v", "q4_1",
            "--mlock",
            "--cache-prompt",
            "--cache-reuse", "64",
            "--cache-ram", "128",
            "--metrics"
        ])
        XCTAssertFalse(arguments.contains("--port"))
    }

    func testLaunchArgumentsUseCurrentBuildDefaultTuning() {
        let arguments = BundledModelRuntime.launchArguments(
            modelURL: URL(fileURLWithPath: "/tmp/model.gguf"),
            spec: .builtIn,
            socketURL: URL(fileURLWithPath: "/tmp/stillloop-runtime.sock")
        )

        #if DEBUG
        XCTAssertFalse(arguments.contains("--batch-size"))
        XCTAssertFalse(arguments.contains("--ubatch-size"))
        XCTAssertEqual(arguments.last, "--metrics")
        #else
        XCTAssertFalse(arguments.contains("--batch-size"))
        XCTAssertFalse(arguments.contains("--ubatch-size"))
        XCTAssertFalse(arguments.contains("--metrics"))
        #endif
    }

    func testDefaultUnixSocketPathKeepsShortFilenameForSandboxContainerPaths() throws {
        let arguments = BundledModelRuntime.launchArguments(
            modelURL: URL(fileURLWithPath: "/tmp/model.gguf"),
            spec: .builtIn
        )
        let hostIndex = try XCTUnwrap(arguments.firstIndex(of: "--host"))
        let socketPath = arguments[hostIndex + 1]
        let address = sockaddr_un()
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)

        XCTAssertTrue(URL(fileURLWithPath: socketPath).lastPathComponent.hasPrefix("sl-"))
        XCTAssertLessThanOrEqual(socketPath.utf8CString.count, pathCapacity)
    }

    func testLaunchArgumentsCanUseProductionTuningWithoutDevelopmentDiagnostics() {
        let modelURL = URL(fileURLWithPath: "/tmp/model.gguf")

        let arguments = BundledModelRuntime.launchArguments(
            modelURL: modelURL,
            spec: .builtIn,
            socketURL: URL(fileURLWithPath: "/tmp/stillloop-runtime.sock"),
            tuning: .production
        )

        XCTAssertFalse(arguments.contains("--batch-size"))
        XCTAssertFalse(arguments.contains("--ubatch-size"))
        XCTAssertFalse(arguments.contains("--metrics"))
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--ctx-size")! + 1], "12288")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--parallel")! + 1], "3")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--n-gpu-layers")! + 1], "99")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--cache-type-k")! + 1], "q4_1")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--cache-type-v")! + 1], "q4_1")
        XCTAssertTrue(arguments.contains("--mlock"))
        XCTAssertTrue(arguments.contains("--cache-prompt"))
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--cache-reuse")! + 1], "64")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--cache-ram")! + 1], "128")
        XCTAssertFalse(arguments.contains("--no-cache-prompt"))
    }

    func testLaunchArgumentsCanDisablePromptCacheForRuntimeComparison() {
        let arguments = BundledModelRuntime.launchArguments(
            modelURL: URL(fileURLWithPath: "/tmp/model.gguf"),
            spec: .builtIn,
            socketURL: URL(fileURLWithPath: "/tmp/stillloop-runtime.sock"),
            tuning: BundledModelRuntime.LaunchTuning(metricsEnabled: true, promptCacheEnabled: false)
        )

        XCTAssertFalse(arguments.contains("--cache-prompt"))
        XCTAssertFalse(arguments.contains("--cache-reuse"))
        XCTAssertFalse(arguments.contains("--cache-ram"))
        XCTAssertTrue(arguments.contains("--metrics"))
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--ctx-size")! + 1], "12288")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--parallel")! + 1], "3")
    }

    func testDefaultTuningCanDisablePromptCacheFromEnvironmentForRuntimeComparison() {
        let tuning = BundledModelRuntime.LaunchTuning.resolvedDefault(
            environment: ["STILLLOOP_DISABLE_PROMPT_CACHE": "1"]
        )

        XCTAssertFalse(tuning.promptCacheEnabled)
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

    func testStartReusesHealthyStillLoopHelperOnSocket() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = try makeProjectorFile()
        let socketURL = makeSocketURL()
        let expectedBaseURL = OpenAICompatibleLLMEngine.unixSocketBaseURL(socketURL: socketURL)
        let launcher = FakeBundledModelProcessLauncher()
        let helper = makeHelperOccupant(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            socketURL: socketURL
        )
        var probedBaseURLs: [URL] = []
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            socketURL: socketURL,
            spec: .builtIn,
            processLauncher: launcher,
            helperProcesses: { [helper] },
            readinessProbe: { baseURL, _ in
                probedBaseURLs.append(baseURL)
                return .ready
            }
        )

        try await runtime.startIfNeeded()

        XCTAssertEqual(launcher.launchCount, 0)
        XCTAssertEqual(probedBaseURLs, [expectedBaseURL])
        XCTAssertEqual(runtime.baseURL, expectedBaseURL)
        XCTAssertEqual(runtime.state, .running)
    }

    func testStartTerminatesDuplicateStillLoopHelpersOnSocketInsteadOfAdoptingOne() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = try makeProjectorFile()
        let socketURL = makeSocketURL()
        let launcher = FakeBundledModelProcessLauncher()
        let firstHelper = makeHelperOccupant(
            pid: 41,
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            socketURL: socketURL
        )
        let secondHelper = makeHelperOccupant(
            pid: 42,
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            socketURL: socketURL
        )
        var terminatedOccupants: [BundledModelPortOccupant] = []
        var runningHelpers = [firstHelper, secondHelper]
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            socketURL: socketURL,
            spec: .builtIn,
            processLauncher: launcher,
            helperProcesses: { runningHelpers },
            terminatePortOccupant: { occupant in
                terminatedOccupants.append(occupant)
                runningHelpers.removeAll { $0.pid == occupant.pid }
            },
            readinessProbe: { _, _ in .ready },
            processExitRetryDelayNanoseconds: 0
        )

        try await runtime.startIfNeeded()

        XCTAssertEqual(terminatedOccupants, [firstHelper, secondHelper])
        XCTAssertEqual(launcher.launchCount, 1)
        XCTAssertEqual(runtime.baseURL, OpenAICompatibleLLMEngine.unixSocketBaseURL(socketURL: socketURL))
        XCTAssertEqual(runtime.state, .running)
    }

    func testStartDoesNotLaunchNewRuntimeWhenDuplicateHelpersDoNotExit() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = try makeProjectorFile()
        let socketURL = makeSocketURL()
        let launcher = FakeBundledModelProcessLauncher()
        let firstHelper = makeHelperOccupant(
            pid: 41,
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            socketURL: socketURL
        )
        let secondHelper = makeHelperOccupant(
            pid: 42,
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            socketURL: socketURL
        )
        var terminatedOccupants: [BundledModelPortOccupant] = []
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            socketURL: socketURL,
            spec: .builtIn,
            processLauncher: launcher,
            helperProcesses: { [firstHelper, secondHelper] },
            terminatePortOccupant: { terminatedOccupants.append($0) },
            readinessProbe: { _, _ in .ready },
            processExitMaxAttempts: 1,
            processExitRetryDelayNanoseconds: 0
        )

        do {
            try await runtime.startIfNeeded()
            XCTFail("Expected duplicate helpers that do not exit to block a new helper launch")
        } catch let error as BundledModelRuntime.RuntimeError {
            XCTAssertEqual(error, .launchFailed("existing stillloop-llama-server helpers did not exit"))
            XCTAssertEqual(terminatedOccupants, [firstHelper, secondHelper])
            XCTAssertEqual(launcher.launchCount, 0)
            XCTAssertEqual(runtime.state, .failed("启动失败"))
        }
    }

    func testStopTerminatesAdoptedStillLoopHelper() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = try makeProjectorFile()
        let socketURL = makeSocketURL()
        let helper = makeHelperOccupant(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            socketURL: socketURL
        )
        var terminatedOccupants: [BundledModelPortOccupant] = []
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            socketURL: socketURL,
            spec: .builtIn,
            helperProcesses: { [helper] },
            terminatePortOccupant: { terminatedOccupants.append($0) },
            readinessProbe: { _, _ in .ready }
        )

        try await runtime.startIfNeeded()
        runtime.stop()

        XCTAssertEqual(terminatedOccupants, [helper])
        XCTAssertEqual(runtime.state, .stopped)
    }

    func testStopTerminatesVerifiedHelperEvenWhenItMatchesOwnedProcessIdentifier() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = try makeProjectorFile()
        let socketURL = makeSocketURL()
        let launcher = FakeBundledModelProcessLauncher()
        var helperProcesses: [BundledModelPortOccupant] = []
        var terminatedOccupants: [BundledModelPortOccupant] = []
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            socketURL: socketURL,
            spec: .builtIn,
            processLauncher: launcher,
            helperProcesses: { helperProcesses },
            terminatePortOccupant: { terminatedOccupants.append($0) },
            readinessProbe: { _, _ in .ready },
            processExitRetryDelayNanoseconds: 0
        )

        try await runtime.startIfNeeded()
        let process = try XCTUnwrap(launcher.launchedProcesses.first)
        helperProcesses = [
            makeHelperOccupant(
                pid: process.processIdentifier,
                executableURL: executableURL,
                modelURL: modelURL,
                mmprojURL: mmprojURL,
                socketURL: socketURL
            )
        ]

        runtime.stop()

        XCTAssertEqual(process.terminateCount, 1)
        XCTAssertEqual(terminatedOccupants, helperProcesses)
        XCTAssertEqual(runtime.state, .stopped)
    }

    func testStartTerminatesStaleStillLoopHelperOnSocketThenRestarts() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = try makeProjectorFile()
        let socketURL = makeSocketURL()
        let launcher = FakeBundledModelProcessLauncher()
        let staleHelper = makeHelperOccupant(
            pid: 44,
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            socketURL: socketURL
        )
        var terminatedOccupants: [BundledModelPortOccupant] = []
        var runningHelpers = [staleHelper]
        var probeCount = 0
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            socketURL: socketURL,
            spec: .builtIn,
            processLauncher: launcher,
            helperProcesses: { runningHelpers },
            terminatePortOccupant: { occupant in
                terminatedOccupants.append(occupant)
                runningHelpers.removeAll { $0.pid == occupant.pid }
            },
            readinessProbe: { _, _ in
                probeCount += 1
                if probeCount == 1 {
                    throw URLError(.cannotConnectToHost)
                }
                return .ready
            },
            processExitRetryDelayNanoseconds: 0
        )

        try await runtime.startIfNeeded()

        XCTAssertEqual(terminatedOccupants, [staleHelper])
        XCTAssertEqual(launcher.launchCount, 1)
        XCTAssertEqual(
            launcher.lastArguments,
            BundledModelRuntime.launchArguments(modelURL: modelURL, mmprojURL: mmprojURL, spec: .builtIn, socketURL: socketURL)
        )
        XCTAssertEqual(runtime.baseURL, OpenAICompatibleLLMEngine.unixSocketBaseURL(socketURL: socketURL))
    }

    func testStartDoesNotReuseOrTerminateHelpersWithMismatchedIdentityArguments() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = try makeProjectorFile()
        let socketURL = makeSocketURL()
        let launcher = FakeBundledModelProcessLauncher()
        let matchingNameWrongPath = BundledModelPortOccupant(
            pid: 45,
            executablePath: temporaryDirectory
                .appendingPathComponent("OtherHelpers", isDirectory: true)
                .appendingPathComponent("stillloop-llama-server")
                .path,
            arguments: BundledModelRuntime.launchArguments(
                modelURL: modelURL,
                mmprojURL: mmprojURL,
                spec: .builtIn,
                socketURL: socketURL
            )
        )
        let wrongSocket = BundledModelPortOccupant(
            pid: 46,
            executablePath: executableURL.path,
            arguments: [
                executableURL.path,
                "-m", modelURL.path,
                "--mmproj", mmprojURL.path,
                "--host", temporaryDirectory.appendingPathComponent("other.sock").path
            ]
        )
        let wrongModel = BundledModelPortOccupant(
            pid: 48,
            executablePath: executableURL.path,
            arguments: [
                executableURL.path,
                "-m", temporaryDirectory.appendingPathComponent("other-model.gguf").path,
                "--mmproj", mmprojURL.path,
                "--host", socketURL.path
            ]
        )
        let wrongProjector = BundledModelPortOccupant(
            pid: 49,
            executablePath: executableURL.path,
            arguments: [
                executableURL.path,
                "-m", modelURL.path,
                "--mmproj", temporaryDirectory.appendingPathComponent("other-mmproj.gguf").path,
                "--host", socketURL.path
            ]
        )
        var terminatedOccupants: [BundledModelPortOccupant] = []
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            socketURL: socketURL,
            spec: .builtIn,
            processLauncher: launcher,
            helperProcesses: { [
                matchingNameWrongPath,
                wrongSocket,
                wrongModel,
                wrongProjector
            ] },
            terminatePortOccupant: { terminatedOccupants.append($0) },
            readinessProbe: { _, _ in .ready }
        )

        try await runtime.startIfNeeded()

        XCTAssertEqual(terminatedOccupants, [])
        XCTAssertEqual(launcher.launchCount, 1)
        XCTAssertEqual(
            launcher.lastArguments,
            BundledModelRuntime.launchArguments(modelURL: modelURL, mmprojURL: mmprojURL, spec: .builtIn, socketURL: socketURL)
        )
        XCTAssertEqual(runtime.baseURL, OpenAICompatibleLLMEngine.unixSocketBaseURL(socketURL: socketURL))
    }

    func testStartTerminatesLegacyStillLoopHelperOnSocketThenRestarts() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = try makeProjectorFile()
        let socketURL = makeSocketURL()
        let launcher = FakeBundledModelProcessLauncher()
        let legacyExecutableURL = executableURL.deletingLastPathComponent().appendingPathComponent("llama-server")
        let staleHelper = BundledModelPortOccupant(
            pid: 43,
            executablePath: legacyExecutableURL.path,
            arguments: [
                legacyExecutableURL.path,
                "-m", modelURL.path,
                "--mmproj", mmprojURL.path,
                "--host", socketURL.path
            ]
        )
        var terminatedOccupants: [BundledModelPortOccupant] = []
        var runningHelpers = [staleHelper]
        var probeCount = 0
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            socketURL: socketURL,
            spec: .builtIn,
            processLauncher: launcher,
            helperProcesses: { runningHelpers },
            terminatePortOccupant: { occupant in
                terminatedOccupants.append(occupant)
                runningHelpers.removeAll { $0.pid == occupant.pid }
            },
            readinessProbe: { _, _ in
                probeCount += 1
                if probeCount == 1 {
                    throw URLError(.cannotConnectToHost)
                }
                return .ready
            },
            processExitRetryDelayNanoseconds: 0
        )

        try await runtime.startIfNeeded()

        XCTAssertEqual(terminatedOccupants, [staleHelper])
        XCTAssertEqual(launcher.launchCount, 1)
        XCTAssertEqual(runtime.baseURL, OpenAICompatibleLLMEngine.unixSocketBaseURL(socketURL: socketURL))
    }

    func testStartLaunchesProcessAndRequiresImageReadiness() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let mmprojURL = try makeProjectorFile()
        let socketURL = makeSocketURL()
        let launcher = FakeBundledModelProcessLauncher()
        var probedBaseURL: URL?
        var probedModelID: String?
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            mmprojURL: mmprojURL,
            socketURL: socketURL,
            spec: .builtIn,
            processLauncher: launcher,
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
            BundledModelRuntime.launchArguments(modelURL: modelURL, mmprojURL: mmprojURL, spec: .builtIn, socketURL: socketURL)
        )
        XCTAssertEqual(probedBaseURL, OpenAICompatibleLLMEngine.unixSocketBaseURL(socketURL: socketURL))
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

    func testStartReusesRunningProcessWhenSocketReadinessSucceeds() async throws {
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
            readinessProbe: { _, _ in .ready },
            processExitRetryDelayNanoseconds: 0
        )

        try await runtime.startIfNeeded()
        try await runtime.startIfNeeded()

        XCTAssertEqual(launcher.launchCount, 1)
        XCTAssertEqual(runtime.state, .running)
    }

    func testStartStopsRunningOwnedProcessWhenSocketReadinessFails() async throws {
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
            readinessProbe: { _, _ in
                probeCount += 1
                if probeCount == 2 {
                    throw URLError(.cannotConnectToHost)
                }
                return .ready
            },
            readinessMaxAttempts: 1,
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
        for _ in 0..<100 where process.isRunning {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let isStillRunning = process.isRunning
        if isStillRunning {
            process.terminate()
        }

        XCTAssertFalse(isStillRunning, "A helper that writes lots of logs should be drained instead of blocking on a full pipe")
    }

    func testFoundationLauncherStopsHelperWhenParentProcessDisappears() async throws {
        let executableURL = temporaryDirectory.appendingPathComponent("long-running-helper")
        try """
        #!/bin/sh
        while true; do
          sleep 1
        done
        """.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let process = try FoundationBundledModelProcessLauncher(parentProcessIdentifier: 999_999).launch(
            executableURL: executableURL,
            arguments: []
        )
        for _ in 0..<30 where process.isRunning {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let isStillRunning = process.isRunning
        if isStillRunning {
            process.terminate()
        }

        XCTAssertFalse(isStillRunning, "A helper should stop when the launching app process is gone")
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

    private func makeSocketURL() -> URL {
        temporaryDirectory.appendingPathComponent("runtime.sock")
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

    private func makeHelperOccupant(
        pid: Int32 = 42,
        executableURL: URL,
        modelURL: URL,
        mmprojURL: URL,
        socketURL: URL
    ) -> BundledModelPortOccupant {
        BundledModelPortOccupant(
            pid: pid,
            executablePath: executableURL.path,
            arguments: BundledModelRuntime.launchArguments(
                modelURL: modelURL,
                mmprojURL: mmprojURL,
                spec: .builtIn,
                socketURL: socketURL
            )
        )
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
