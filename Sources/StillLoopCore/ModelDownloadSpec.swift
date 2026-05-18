import Foundation

public struct ModelDownloadSpec: Equatable {
    public let repoID: String
    public let filename: String
    public let mmprojFilename: String?
    public let localSubdirectory: String
    public let localServerModelID: String
    public let localServerPort: Int
    public let recommendedContextSize: Int
    public let recommendedCacheTypeK: String
    public let recommendedCacheTypeV: String

    public var modelPageURL: URL {
        URL(string: "https://huggingface.co/\(repoID)")!
    }

    public var downloadURL: URL {
        downloadURL(for: filename)
    }

    public var mmprojDownloadURL: URL? {
        mmprojFilename.map(downloadURL(for:))
    }

    public var requiredFilenames: [String] {
        var filenames = [filename]
        if let mmprojFilename {
            filenames.append(mmprojFilename)
        }
        return filenames
    }

    public func downloadURL(for filename: String) -> URL {
        let encoded = filename
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        return URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(encoded)")!
    }

    public var localServerBaseURL: URL {
        localServerBaseURL(port: localServerPort)
    }

    public func localServerBaseURL(port: Int) -> URL {
        URL(string: "http://127.0.0.1:\(port)/v1")!
    }

    public static let builtIn = ModelDownloadSpec(
        repoID: "twinblade02/Qwen3.5VL-0.8B-ImageExplainer-GGUF",
        filename: "Qwen3.5-0.8B-Base.Q4_K_M.gguf",
        mmprojFilename: "Qwen3.5-0.8B-Base.BF16-mmproj.gguf",
        localSubdirectory: "Qwen3.5VL-0.8B-ImageExplainer-GGUF",
        localServerModelID: "Qwen3.5-0.8B-Base.Q4_K_M.gguf",
        localServerPort: 17_631,
        recommendedContextSize: 32_768,
        recommendedCacheTypeK: "f16",
        recommendedCacheTypeV: "f16"
    )
}
