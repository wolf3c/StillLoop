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
            "--ctx-size", "4096",
            "--parallel", "1",
            "--n-gpu-layers", "99",
            "--batch-size", "4096",
            "--ubatch-size", "4096",
            "--cache-type-k", "q4_1",
            "--cache-type-v", "q4_1",
            "--mlock",
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
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--batch-size")! + 1], "4096")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--ubatch-size")! + 1], "4096")
        XCTAssertFalse(arguments.contains("--flash-attn"))
        XCTAssertFalse(arguments.contains("--cache-prompt"))
        XCTAssertEqual(arguments.last, "--metrics")
        #else
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--batch-size")! + 1], "4096")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--ubatch-size")! + 1], "4096")
        XCTAssertFalse(arguments.contains("--flash-attn"))
        XCTAssertFalse(arguments.contains("--cache-prompt"))
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

        XCTAssertEqual(arguments[arguments.firstIndex(of: "--batch-size")! + 1], "4096")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--ubatch-size")! + 1], "4096")
        XCTAssertFalse(arguments.contains("--flash-attn"))
        XCTAssertFalse(arguments.contains("--metrics"))
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--ctx-size")! + 1], "4096")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--parallel")! + 1], "1")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--n-gpu-layers")! + 1], "99")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--cache-type-k")! + 1], "q4_1")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--cache-type-v")! + 1], "q4_1")
        XCTAssertTrue(arguments.contains("--mlock"))
        XCTAssertFalse(arguments.contains("--cache-prompt"))
        XCTAssertFalse(arguments.contains("--cache-reuse"))
        XCTAssertFalse(arguments.contains("--cache-ram"))
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
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--ctx-size")! + 1], "4096")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--parallel")! + 1], "1")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--batch-size")! + 1], "4096")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--ubatch-size")! + 1], "4096")
        XCTAssertFalse(arguments.contains("--flash-attn"))
    }

    func testDefaultTuningKeepsPromptCacheDisabledForRuntimeComparison() {
        let tuning = BundledModelRuntime.LaunchTuning.resolvedDefault(
            environment: [:]
        )

        XCTAssertFalse(tuning.promptCacheEnabled)
    }

    func testBundledRuntimeSelectionDefaultsToLlamaCppRuntime() {
        let modelURL = URL(fileURLWithPath: "/tmp/model.gguf")

        let runtime = BundledRuntimeSelection.makeDefaultRuntime(modelURL: modelURL)
        let diagnostics = runtime as? BundledRuntimeDiagnosticsProviding

        XCTAssertEqual(BundledRuntimeSelection.defaultKind, .llamaCpp)
        XCTAssertEqual(diagnostics?.bundledRuntimeKind, .llamaCpp)
        XCTAssertNil(diagnostics?.fallbackRuntimeKind)
    }

    func testBundledRuntimeSelectionCanBuildLlamaCppRuntimeDirectly() {
        let modelURL = URL(fileURLWithPath: "/tmp/model.gguf")

        let runtime = BundledRuntimeSelection.makeRuntime(kind: .llamaCpp, modelURL: modelURL)
        let diagnostics = runtime as? BundledRuntimeDiagnosticsProviding

        XCTAssertEqual(diagnostics?.bundledRuntimeKind, .llamaCpp)
        XCTAssertNil(diagnostics?.fallbackRuntimeKind)
    }

    func testBundledRuntimeSelectionCanBuildRapidMLXRuntimeWithLlamaFallback() {
        let modelURL = URL(fileURLWithPath: "/tmp/model.gguf")

        let runtime = BundledRuntimeSelection.makeDefaultRuntime(
            kind: .rapidMlx,
            modelURL: modelURL
        )
        let diagnostics = runtime as? BundledRuntimeDiagnosticsProviding

        XCTAssertTrue(runtime is FallbackBundledModelRuntime)
        XCTAssertEqual(diagnostics?.bundledRuntimeKind, .rapidMlx)
        XCTAssertNil(diagnostics?.fallbackRuntimeKind)
    }

    func testBundledRuntimeSelectionCanBuildRapidMLXRuntimeDirectly() {
        let modelURL = URL(fileURLWithPath: "/tmp/model.gguf")

        let runtime = BundledRuntimeSelection.makeRuntime(kind: .rapidMlx, modelURL: modelURL)
        let diagnostics = runtime as? BundledRuntimeDiagnosticsProviding

        XCTAssertEqual(diagnostics?.bundledRuntimeKind, .rapidMlx)
        XCTAssertNil(diagnostics?.fallbackRuntimeKind)
    }

    func testBundledRuntimeSelectionResolvesUnknownKindToDefault() {
        let resolvedKind = BundledRuntimeSelection.runtimeKind(
            environment: ["STILLLOOP_BUNDLED_RUNTIME": "somethingElse"]
        )
        let modelURL = URL(fileURLWithPath: "/tmp/model.gguf")
        let runtime = BundledRuntimeSelection.makeRuntime(
            kind: resolvedKind,
            modelURL: modelURL
        )
        let diagnostics = runtime as? BundledRuntimeDiagnosticsProviding

        XCTAssertEqual(resolvedKind, .llamaCpp)
        XCTAssertEqual(diagnostics?.bundledRuntimeKind, .llamaCpp)
    }

    func testBundledRuntimeSelectionResolvesExplicitLlamaKindFromEnvironment() {
        let resolvedKind = BundledRuntimeSelection.runtimeKind(
            environment: ["STILLLOOP_BUNDLED_RUNTIME": "llamaCpp"]
        )

        XCTAssertEqual(resolvedKind, .llamaCpp)
    }

    func testBundledRuntimeSelectionResolvesExplicitRapidKindFromEnvironment() {
        let resolvedKind = BundledRuntimeSelection.runtimeKind(
            environment: ["STILLLOOP_BUNDLED_RUNTIME": "rapidMlx"]
        )

        XCTAssertEqual(resolvedKind, .rapidMlx)
    }

    func testMLXRuntimeEnablesInMemoryAPCByDefault() {
        let configuration = MLXBundledModelRuntime.Configuration.localDevelopment(port: 18765)
        let apcIndex = configuration.arguments.firstIndex(of: "APC_ENABLED=1")
        let pythonIndex = configuration.arguments.firstIndex(of: "python3")

        XCTAssertNotNil(apcIndex)
        XCTAssertNotNil(pythonIndex)
        XCTAssertLessThan(try XCTUnwrap(apcIndex), try XCTUnwrap(pythonIndex))
        XCTAssertFalse(configuration.arguments.contains { $0.hasPrefix("APC_DISK_PATH=") })
    }

    func testMLXRuntimeCacheTuningCanDisableAPC() {
        let configuration = MLXBundledModelRuntime.Configuration.localDevelopment(
            port: 18765,
            cacheTuning: MLXRuntimeCacheTuning(apcEnabled: false)
        )

        XCTAssertFalse(configuration.arguments.contains("APC_ENABLED=1"))
        XCTAssertFalse(configuration.arguments.contains { $0.hasPrefix("APC_DISK_PATH=") })
    }

    func testRapidMLXRuntimeLaunchArgumentsMatchRapidServe() {
        let configuration = RapidMLXBundledModelRuntime.Configuration.localDevelopment(port: 18765)

        XCTAssertEqual(configuration.arguments, [
            "rapid-mlx",
            "serve",
            "mlx-community/Qwen3.5-0.8B-4bit",
            "--mllm",
            "--host", "127.0.0.1",
            "--port", "18765",
            "--max-tokens", "900"
        ])
    }

    func testRapidMLXRuntimeUsesExplicitExecutablePath() {
        let explicitPath = URL(fileURLWithPath: "/tmp/rapid-mlx-explicit")
        let configuration = RapidMLXBundledModelRuntime.Configuration.localDevelopment(
            port: 18765,
            executableURL: explicitPath
        )

        XCTAssertEqual(configuration.executableURL, explicitPath)
        XCTAssertEqual(configuration.arguments, [
            "serve",
            "mlx-community/Qwen3.5-0.8B-4bit",
            "--mllm",
            "--host", "127.0.0.1",
            "--port", "18765",
            "--max-tokens", "900"
        ])
    }

    func testRapidMLXRuntimeLaunchArgumentsAcceptsLocalModelPathOverride() {
        let modelPath = "/tmp/Models/Qwen3.5-0.8B-Base.Q4_K_M.gguf"
        let configuration = RapidMLXBundledModelRuntime.Configuration.localDevelopment(
            port: 18765,
            modelIdentifier: modelPath
        )

        XCTAssertEqual(configuration.arguments[2], modelPath)
        XCTAssertEqual(configuration.modelID, modelPath)
    }

    func testFallbackRuntimeUsesPrimaryWhenMLXStarts() async throws {
        let mlx = FakeSelectableBundledRuntime(kind: .mlx)
        let llama = FakeSelectableBundledRuntime(kind: .llamaCpp)
        let runtime = FallbackBundledModelRuntime(primary: mlx, fallback: llama)

        try await runtime.startIfNeeded()

        XCTAssertEqual(mlx.startCount, 1)
        XCTAssertEqual(llama.startCount, 0)
        XCTAssertEqual(runtime.baseURL, mlx.baseURL)
        XCTAssertEqual(runtime.modelID, mlx.modelID)
        XCTAssertEqual(runtime.state, .running)
        XCTAssertEqual(runtime.bundledRuntimeKind, .mlx)
        XCTAssertNil(runtime.fallbackRuntimeKind)
    }

    func testFallbackRuntimeUsesPrimaryWhenRapidMLXStarts() async throws {
        let rapidMlx = FakeSelectableBundledRuntime(kind: .rapidMlx)
        let llama = FakeSelectableBundledRuntime(kind: .llamaCpp)
        let runtime = FallbackBundledModelRuntime(primary: rapidMlx, fallback: llama)

        try await runtime.startIfNeeded()

        XCTAssertEqual(rapidMlx.startCount, 1)
        XCTAssertEqual(llama.startCount, 0)
        XCTAssertEqual(runtime.baseURL, rapidMlx.baseURL)
        XCTAssertEqual(runtime.modelID, rapidMlx.modelID)
        XCTAssertEqual(runtime.state, .running)
        XCTAssertEqual(runtime.bundledRuntimeKind, .rapidMlx)
        XCTAssertNil(runtime.fallbackRuntimeKind)
    }

    func testFallbackRuntimeStartsLlamaWhenMLXReadinessFails() async throws {
        let mlx = FakeSelectableBundledRuntime(kind: .mlx)
        mlx.startError = BundledModelRuntime.RuntimeError.readinessFailed("timeout")
        let llama = FakeSelectableBundledRuntime(kind: .llamaCpp)
        let runtime = FallbackBundledModelRuntime(primary: mlx, fallback: llama)

        try await runtime.startIfNeeded()

        XCTAssertEqual(mlx.startCount, 1)
        XCTAssertEqual(mlx.stopCount, 1)
        XCTAssertEqual(llama.startCount, 1)
        XCTAssertEqual(runtime.baseURL, llama.baseURL)
        XCTAssertEqual(runtime.modelID, llama.modelID)
        XCTAssertEqual(runtime.state, .running)
        XCTAssertEqual(runtime.bundledRuntimeKind, .llamaCpp)
        XCTAssertEqual(runtime.fallbackRuntimeKind, .llamaCpp)
    }

    func testFallbackRuntimeStartsLlamaWhenRapidMLXReadinessFails() async throws {
        let rapidMlx = FakeSelectableBundledRuntime(kind: .rapidMlx)
        rapidMlx.startError = BundledModelRuntime.RuntimeError.readinessFailed("timeout")
        let llama = FakeSelectableBundledRuntime(kind: .llamaCpp)
        let runtime = FallbackBundledModelRuntime(primary: rapidMlx, fallback: llama)

        try await runtime.startIfNeeded()

        XCTAssertEqual(rapidMlx.startCount, 1)
        XCTAssertEqual(rapidMlx.stopCount, 1)
        XCTAssertEqual(llama.startCount, 1)
        XCTAssertEqual(runtime.baseURL, llama.baseURL)
        XCTAssertEqual(runtime.modelID, llama.modelID)
        XCTAssertEqual(runtime.state, .running)
        XCTAssertEqual(runtime.bundledRuntimeKind, .llamaCpp)
        XCTAssertEqual(runtime.fallbackRuntimeKind, .llamaCpp)
    }

    func testFallbackRuntimeStartsLlamaWhenRapidMLXImageInputIsUnavailable() async throws {
        let rapidMlx = FakeSelectableBundledRuntime(kind: .rapidMlx)
        rapidMlx.startError = BundledModelRuntime.RuntimeError.imageInputUnavailable
        let llama = FakeSelectableBundledRuntime(kind: .llamaCpp)
        let runtime = FallbackBundledModelRuntime(primary: rapidMlx, fallback: llama)

        try await runtime.startIfNeeded()

        XCTAssertEqual(rapidMlx.stopCount, 1)
        XCTAssertEqual(llama.startCount, 1)
        XCTAssertEqual(runtime.bundledRuntimeKind, .llamaCpp)
        XCTAssertEqual(runtime.fallbackRuntimeKind, .llamaCpp)
    }

    func testFallbackRuntimeThrowsLlamaFailureWhenRapidMLXAndLlamaBothFail() async throws {
        let rapidMlx = FakeSelectableBundledRuntime(kind: .rapidMlx)
        rapidMlx.startError = BundledModelRuntime.RuntimeError.readinessFailed("timeout")
        let llama = FakeSelectableBundledRuntime(kind: .llamaCpp)
        llama.startError = BundledModelRuntime.RuntimeError.missingExecutable(URL(fileURLWithPath: "/tmp/missing"))
        let runtime = FallbackBundledModelRuntime(primary: rapidMlx, fallback: llama)

        do {
            try await runtime.startIfNeeded()
            XCTFail("Expected fallback runtime failure")
        } catch let error as BundledModelRuntime.RuntimeError {
            XCTAssertEqual(error, .missingExecutable(URL(fileURLWithPath: "/tmp/missing")))
            XCTAssertEqual(rapidMlx.stopCount, 1)
            XCTAssertEqual(llama.startCount, 1)
            XCTAssertEqual(runtime.state, .failed("缺少 stillloop-llama-server"))
            XCTAssertEqual(runtime.bundledRuntimeKind, .llamaCpp)
            XCTAssertEqual(runtime.fallbackRuntimeKind, .llamaCpp)
        }
    }

    func testFallbackRuntimeStartsLlamaWhenMLXImageInputIsUnavailable() async throws {
        let mlx = FakeSelectableBundledRuntime(kind: .mlx)
        mlx.startError = BundledModelRuntime.RuntimeError.imageInputUnavailable
        let llama = FakeSelectableBundledRuntime(kind: .llamaCpp)
        let runtime = FallbackBundledModelRuntime(primary: mlx, fallback: llama)

        try await runtime.startIfNeeded()

        XCTAssertEqual(mlx.stopCount, 1)
        XCTAssertEqual(llama.startCount, 1)
        XCTAssertEqual(runtime.bundledRuntimeKind, .llamaCpp)
        XCTAssertEqual(runtime.fallbackRuntimeKind, .llamaCpp)
    }

    func testFallbackRuntimeThrowsLlamaFailureWhenBothRuntimesFail() async throws {
        let mlx = FakeSelectableBundledRuntime(kind: .mlx)
        mlx.startError = BundledModelRuntime.RuntimeError.readinessFailed("timeout")
        let llama = FakeSelectableBundledRuntime(kind: .llamaCpp)
        llama.startError = BundledModelRuntime.RuntimeError.missingExecutable(URL(fileURLWithPath: "/tmp/missing"))
        let runtime = FallbackBundledModelRuntime(primary: mlx, fallback: llama)

        do {
            try await runtime.startIfNeeded()
            XCTFail("Expected fallback runtime failure")
        } catch let error as BundledModelRuntime.RuntimeError {
            XCTAssertEqual(error, .missingExecutable(URL(fileURLWithPath: "/tmp/missing")))
            XCTAssertEqual(mlx.stopCount, 1)
            XCTAssertEqual(llama.startCount, 1)
            XCTAssertEqual(runtime.state, .failed("缺少 stillloop-llama-server"))
            XCTAssertEqual(runtime.bundledRuntimeKind, .llamaCpp)
            XCTAssertEqual(runtime.fallbackRuntimeKind, .llamaCpp)
        }
    }

    func testMLXRuntimeStopsWaitingWhenLaunchedProcessExitsBeforeReadiness() async throws {
        let launcher = FakeBundledModelProcessLauncher()
        var probeCount = 0
        let runtime = MLXBundledModelRuntime(
            configuration: .localDevelopment(port: 18765),
            processLauncher: launcher,
            readinessProbe: { _, _ in
                probeCount += 1
                launcher.process.isRunning = false
                throw URLError(.cannotConnectToHost)
            },
            readinessMaxAttempts: 5,
            readinessRetryDelayNanoseconds: 1_000_000
        )

        do {
            try await runtime.startIfNeeded()
            XCTFail("Expected exited MLX process to fail readiness")
        } catch let error as BundledModelRuntime.RuntimeError {
            XCTAssertEqual(error, .launchFailed("mlx-vlm process exited before readiness"))
            XCTAssertEqual(probeCount, 1)
            XCTAssertEqual(runtime.state, .failed("启动失败"))
        }
    }

    func testMLXRuntimeDoesNotReprobeRunningServerAfterReadinessSucceeds() async throws {
        let launcher = FakeBundledModelProcessLauncher()
        var probeCount = 0
        let runtime = MLXBundledModelRuntime(
            configuration: .localDevelopment(port: 18765),
            processLauncher: launcher,
            readinessProbe: { _, _ in
                probeCount += 1
                if probeCount > 1 {
                    throw URLError(.cannotConnectToHost)
                }
                return .ready
            },
            readinessMaxAttempts: 1,
            readinessRetryDelayNanoseconds: 0,
            processExitRetryDelayNanoseconds: 0
        )

        try await runtime.startIfNeeded()
        let runningProcess = try XCTUnwrap(launcher.launchedProcesses.last)

        try await runtime.startIfNeeded()

        XCTAssertEqual(probeCount, 1)
        XCTAssertEqual(runningProcess.terminateCount, 0)
        XCTAssertTrue(runningProcess.isRunning)
        XCTAssertEqual(launcher.launchCount, 1)
        XCTAssertEqual(runtime.state, .running)
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

private final class FakeSelectableBundledRuntime: BundledModelRuntimeManaging, BundledRuntimeDiagnosticsProviding {
    let kind: BundledRuntimeKind
    var baseURL: URL
    var modelID: String
    var state: BundledModelRuntime.State = .notStarted
    var startError: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(kind: BundledRuntimeKind) {
        self.kind = kind
        baseURL = URL(string: "http://127.0.0.1/\(kind.rawValue)/v1")!
        modelID = "\(kind.rawValue)-model"
    }

    var bundledRuntimeKind: BundledRuntimeKind? {
        state == .running ? kind : kind
    }

    var fallbackRuntimeKind: BundledRuntimeKind? {
        nil
    }

    func startIfNeeded() async throws {
        startCount += 1
        if let startError {
            state = .failed(BundledModelRuntime.RuntimeError.statusMessage(for: startError))
            throw startError
        }
        state = .running
    }

    func stop() {
        stopCount += 1
        state = .stopped
    }
}
