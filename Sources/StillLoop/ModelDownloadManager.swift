import Foundation

struct ModelDownloadManager {
    enum DownloadUpdate {
        case skipped
        case ready
        case checking
        case downloading(String)
        case failed
    }

    struct Manifest: Decodable {
        struct Sibling: Decodable {
            var rfilename: String
        }

        var siblings: [Sibling]
    }

    let repoID = "mlx-community/Qwen3.5-0.8B-OptiQ-4bit"
    let localDirectory: URL

    func isDownloaded() -> Bool {
        FileManager.default.fileExists(atPath: localDirectory.appendingPathComponent("config.json").path)
    }

    func download(progress: @escaping @MainActor (DownloadUpdate) -> Void) async {
        guard ProcessInfo.processInfo.environment["STILLLOOP_SKIP_MODEL_DOWNLOAD"] != "1" else {
            await progress(.skipped)
            return
        }

        if isDownloaded() {
            await progress(.ready)
            return
        }

        do {
            try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
            await progress(.checking)
            let manifest = try await fetchManifest()

            for file in manifest.siblings.map(\.rfilename) where shouldDownload(file) {
                await progress(.downloading(file))
                try await downloadFile(named: file)
            }

            await progress(.ready)
        } catch {
            await progress(.failed)
        }
    }

    private func fetchManifest() async throws -> Manifest {
        let url = URL(string: "https://huggingface.co/api/models/\(repoID)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    private func downloadFile(named filename: String) async throws {
        let encoded = filename
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        let url = URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(encoded)")!
        let destination = localDirectory.appendingPathComponent(filename)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let (temporaryURL, _) = try await URLSession.shared.download(from: url)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }

    private func shouldDownload(_ filename: String) -> Bool {
        !filename.hasPrefix(".") && !filename.lowercased().hasSuffix(".md")
    }
}
