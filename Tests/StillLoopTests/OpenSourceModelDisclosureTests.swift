import XCTest
@testable import StillLoop

final class OpenSourceModelDisclosureTests: XCTestCase {
    func testBuiltInDisclosureNamesQwenBaseModelAndLicense() {
        let disclosure = OpenSourceModelDisclosure.builtIn

        XCTAssertEqual(disclosure.baseModelID, "Qwen/Qwen3.5-0.8B")
        XCTAssertEqual(disclosure.baseModelLicenseName, "Apache License 2.0")
        XCTAssertEqual(
            disclosure.baseModelLicenseURL.absoluteString,
            "https://huggingface.co/Qwen/Qwen3.5-0.8B/blob/main/LICENSE"
        )
    }

    func testBuiltInDisclosureNamesGGUFSourceAndFiles() {
        let disclosure = OpenSourceModelDisclosure.builtIn

        XCTAssertEqual(disclosure.ggufRepositoryID, "twinblade02/Qwen3.5VL-0.8B-ImageExplainer-GGUF")
        XCTAssertEqual(
            disclosure.modelFilenames,
            [
                "Qwen3.5-0.8B-Base.Q4_K_M.gguf",
                "Qwen3.5-0.8B-Base.BF16-mmproj.gguf"
            ]
        )
        XCTAssertEqual(
            disclosure.localModelPathDescription,
            "Application Support/StillLoop/Models/Qwen3.5VL-0.8B-ImageExplainer-GGUF"
        )
        XCTAssertTrue(disclosure.ggufLicenseNote.contains("未提供单独 LICENSE 文件"))
    }

    func testBuiltInDisclosureNamesLlamaRuntimeLicense() {
        let disclosure = OpenSourceModelDisclosure.builtIn

        XCTAssertEqual(disclosure.runtimeName, "llama.cpp / ggml-org b9060 macOS arm64 runtime")
        XCTAssertEqual(disclosure.runtimeLicenseName, "MIT License")
        XCTAssertEqual(disclosure.runtimeCopyright, "Copyright (c) 2023-2026 The ggml authors")
        XCTAssertEqual(disclosure.runtimeLicenseResourceName, "LICENSE.llama.cpp")
        XCTAssertTrue(disclosure.manualModelServiceNote.contains("不由 StillLoop 分发"))
    }
}
