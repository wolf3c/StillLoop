import XCTest
@testable import StillLoopCore

final class ModelDownloadSpecTests: XCTestCase {
    func testBuiltInModelTargetsRequestedGGUFFile() {
        let spec = ModelDownloadSpec.builtIn

        XCTAssertEqual(spec.repoID, "mradermacher/Qwen3.5-0.8B-heretic-ara-high-kld-v3-i1-GGUF")
        XCTAssertEqual(spec.filename, "Qwen3.5-0.8B-heretic-ara-high-kld-v3.i1-IQ4_NL.gguf")
        XCTAssertEqual(spec.localSubdirectory, "Qwen3.5-0.8B-heretic-ara-high-kld-v3-i1-GGUF")
        XCTAssertEqual(spec.localServerModelID, "qwen3.5-0.8b-heretic-ara-high-kld-v3-i1-iq4_nl")
        XCTAssertEqual(
            spec.downloadURL.absoluteString,
            "https://huggingface.co/mradermacher/Qwen3.5-0.8B-heretic-ara-high-kld-v3-i1-GGUF/resolve/main/Qwen3.5-0.8B-heretic-ara-high-kld-v3.i1-IQ4_NL.gguf"
        )
    }
}
