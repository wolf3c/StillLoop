import Foundation
import StillLoopCore

struct ModelDownloadManager {
    enum DownloadUpdate {
        case skipped
        case ready
        case checking
        case downloading(String)
        case paused
        case failed
    }

    let spec: ModelDownloadSpec
    let localDirectory: URL

    func isDownloaded() -> Bool {
        FileManager.default.fileExists(atPath: localDirectory.appendingPathComponent(spec.filename).path)
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
            await progress(.downloading(spec.filename))
            try await downloadFile()
            try Task.checkCancellation()

            await progress(.ready)
        } catch is CancellationError {
            await progress(.paused)
        } catch let error as URLError where error.code == .cancelled {
            await progress(.paused)
        } catch {
            await progress(.failed)
        }
    }

    private func downloadFile() async throws {
        let destination = localDirectory.appendingPathComponent(spec.filename)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let (temporaryURL, _) = try await URLSession.shared.download(from: spec.downloadURL)
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }
}
