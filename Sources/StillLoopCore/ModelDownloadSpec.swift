import Foundation

public struct ModelDownloadSpec: Equatable {
    public let repoID: String
    public let filename: String
    public let localSubdirectory: String
    public let localServerModelID: String

    public var modelPageURL: URL {
        URL(string: "https://huggingface.co/\(repoID)")!
    }

    public var downloadURL: URL {
        let encoded = filename
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        return URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(encoded)")!
    }

    public static let builtIn = ModelDownloadSpec(
        repoID: "mradermacher/Qwen3.5-0.8B-heretic-ara-high-kld-v3-i1-GGUF",
        filename: "Qwen3.5-0.8B-heretic-ara-high-kld-v3.i1-IQ4_NL.gguf",
        localSubdirectory: "Qwen3.5-0.8B-heretic-ara-high-kld-v3-i1-GGUF",
        localServerModelID: "qwen3.5-0.8b-heretic-ara-high-kld-v3-i1-iq4_nl"
    )
}
