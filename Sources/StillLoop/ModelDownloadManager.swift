import Foundation
import StillLoopCore

struct ModelDownloadManager {
    enum DownloadUpdate {
        case skipped
        case ready
        case checking
        case downloading(String, Double?)
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
            try await downloadFile { fraction in
                await progress(.downloading(spec.filename, fraction))
            }
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

    static func progressFraction(completedBytes: Int64, expectedBytes: Int64) -> Double? {
        guard expectedBytes > 0 else { return nil }
        return min(max(Double(completedBytes) / Double(expectedBytes), 0), 1)
    }

    private func downloadFile(progress: @escaping @MainActor (Double?) async -> Void) async throws {
        let destination = localDirectory.appendingPathComponent(spec.filename)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporaryURL = destination.deletingLastPathComponent().appendingPathComponent(".\(spec.filename).download")
        if FileManager.default.fileExists(atPath: temporaryURL.path) {
            try FileManager.default.removeItem(at: temporaryURL)
        }
        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)

        var completedDownload = false
        defer {
            if !completedDownload {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }

        let (bytes, response) = try await URLSession.shared.bytes(from: spec.downloadURL)
        let expectedBytes = response.expectedContentLength
        var completedBytes: Int64 = 0
        var buffer: [UInt8] = []
        buffer.reserveCapacity(64 * 1024)

        let fileHandle = try FileHandle(forWritingTo: temporaryURL)
        defer {
            try? fileHandle.close()
        }

        await progress(Self.progressFraction(completedBytes: completedBytes, expectedBytes: expectedBytes))

        func flushBuffer() throws {
            guard !buffer.isEmpty else { return }
            try fileHandle.write(contentsOf: Data(buffer))
            completedBytes += Int64(buffer.count)
            buffer.removeAll(keepingCapacity: true)
        }

        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try flushBuffer()
                await progress(Self.progressFraction(completedBytes: completedBytes, expectedBytes: expectedBytes))
            }
        }

        try flushBuffer()
        try Task.checkCancellation()
        await progress(Self.progressFraction(completedBytes: completedBytes, expectedBytes: expectedBytes))

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        completedDownload = true
    }
}
