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

        let arguments = BundledModelRuntime.launchArguments(modelURL: modelURL, spec: .builtIn)

        XCTAssertEqual(arguments, [
            "-m", "/tmp/StillLoop Models/model.gguf",
            "--host", "127.0.0.1",
            "--port", "17631",
            "--ctx-size", "32768",
            "--parallel", "1",
            "--n-gpu-layers", "99",
            "--cache-type-k", "f16",
            "--cache-type-v", "f16"
        ])
    }

    func testStartFailsWhenModelFileIsMissingWithoutLaunchingProcess() async throws {
        let executableURL = try makeExecutable()
        let modelURL = temporaryDirectory.appendingPathComponent("missing.gguf")
        let launcher = FakeBundledModelProcessLauncher()
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
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

    func testStartFailsWhenPortIsAlreadyInUseWithoutLaunchingProcess() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let launcher = FakeBundledModelProcessLauncher()
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
            spec: .builtIn,
            processLauncher: launcher,
            isPortInUse: { $0 == ModelDownloadSpec.builtIn.localServerPort },
            readinessProbe: { _, _ in .ready }
        )

        do {
            try await runtime.startIfNeeded()
            XCTFail("Expected occupied port to prevent runtime launch")
        } catch let error as BundledModelRuntime.RuntimeError {
            XCTAssertEqual(error, .portInUse(ModelDownloadSpec.builtIn.localServerPort))
            XCTAssertEqual(launcher.launchCount, 0)
        }
    }

    func testStartLaunchesProcessAndRequiresImageReadiness() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let launcher = FakeBundledModelProcessLauncher()
        var probedBaseURL: URL?
        var probedModelID: String?
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
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
        XCTAssertEqual(launcher.lastArguments, BundledModelRuntime.launchArguments(modelURL: modelURL, spec: .builtIn))
        XCTAssertEqual(probedBaseURL, ModelDownloadSpec.builtIn.localServerBaseURL)
        XCTAssertEqual(probedModelID, ModelDownloadSpec.builtIn.localServerModelID)
        XCTAssertEqual(runtime.state, .running)
    }

    func testStartPollsReadinessUntilServerAcceptsImageRequests() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let launcher = FakeBundledModelProcessLauncher()
        var probeCount = 0
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
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

    func testImageReadinessFailureStopsLaunchedProcess() async throws {
        let executableURL = try makeExecutable()
        let modelURL = try makeModelFile()
        let launcher = FakeBundledModelProcessLauncher()
        let runtime = BundledModelRuntime(
            executableURL: executableURL,
            modelURL: modelURL,
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
        let url = temporaryDirectory.appendingPathComponent("llama-server")
        FileManager.default.createFile(atPath: url.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func makeModelFile() throws -> URL {
        let url = temporaryDirectory.appendingPathComponent("model.gguf")
        FileManager.default.createFile(atPath: url.path, contents: Data("gguf".utf8))
        return url
    }
}

private final class FakeBundledModelProcessLauncher: BundledModelProcessLaunching {
    let process = FakeBundledModelProcess()
    private(set) var launchCount = 0
    private(set) var lastExecutableURL: URL?
    private(set) var lastArguments: [String]?

    func launch(executableURL: URL, arguments: [String]) throws -> BundledModelProcessManaging {
        launchCount += 1
        lastExecutableURL = executableURL
        lastArguments = arguments
        return process
    }
}

private final class FakeBundledModelProcess: BundledModelProcessManaging {
    var isRunning = true
    private(set) var terminateCount = 0

    func terminate() {
        terminateCount += 1
        isRunning = false
    }
}
