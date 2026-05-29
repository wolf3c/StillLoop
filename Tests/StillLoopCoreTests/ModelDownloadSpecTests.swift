import XCTest
@testable import StillLoopCore

final class ModelDownloadSpecTests: XCTestCase {
    func testBuiltInModelTargetsRequestedVisionGGUFAndProjectorFiles() {
        let spec = ModelDownloadSpec.builtIn

        XCTAssertEqual(spec.repoID, "twinblade02/Qwen3.5VL-0.8B-ImageExplainer-GGUF")
        XCTAssertEqual(spec.filename, "Qwen3.5-0.8B-Base.Q4_K_M.gguf")
        XCTAssertEqual(spec.mmprojFilename, "Qwen3.5-0.8B-Base.BF16-mmproj.gguf")
        XCTAssertEqual(spec.requiredFilenames, [
            "Qwen3.5-0.8B-Base.Q4_K_M.gguf",
            "Qwen3.5-0.8B-Base.BF16-mmproj.gguf"
        ])
        XCTAssertEqual(spec.localSubdirectory, "Qwen3.5VL-0.8B-ImageExplainer-GGUF")
        XCTAssertEqual(spec.localServerModelID, "Qwen3.5-0.8B-Base.Q4_K_M.gguf")
        XCTAssertEqual(
            spec.downloadURL.absoluteString,
            "https://huggingface.co/twinblade02/Qwen3.5VL-0.8B-ImageExplainer-GGUF/resolve/main/Qwen3.5-0.8B-Base.Q4_K_M.gguf"
        )
        XCTAssertEqual(
            spec.mmprojDownloadURL?.absoluteString,
            "https://huggingface.co/twinblade02/Qwen3.5VL-0.8B-ImageExplainer-GGUF/resolve/main/Qwen3.5-0.8B-Base.BF16-mmproj.gguf"
        )
    }

    func testBuiltInModelRecommendsDedicatedLlamaServerRuntimeSettings() {
        let spec = ModelDownloadSpec.builtIn

        XCTAssertEqual(spec.localServerPort, 17631)
        XCTAssertEqual(spec.localServerBaseURL.absoluteString, "http://127.0.0.1:17631/v1")
        XCTAssertEqual(spec.localServerBaseURL(port: 17632).absoluteString, "http://127.0.0.1:17632/v1")
        XCTAssertEqual(spec.recommendedContextSize, 16_384)
        XCTAssertEqual(spec.recommendedParallelSlots, 4)
        XCTAssertEqual(spec.recommendedCacheTypeK, "q4_1")
        XCTAssertEqual(spec.recommendedCacheTypeV, "q4_1")
        XCTAssertEqual(spec.recommendedPromptCacheReuse, 64)
        XCTAssertEqual(spec.recommendedPromptCacheRAMMiB, 512)
    }

    func testBuiltInModelDisclosesDownloadSizeForAppReviewPrompt() {
        let spec = ModelDownloadSpec.builtIn

        XCTAssertEqual(spec.totalDownloadBytes, 736_643_008)
        XCTAssertEqual(spec.downloadSizeText, "约 737 MB")
    }
}
