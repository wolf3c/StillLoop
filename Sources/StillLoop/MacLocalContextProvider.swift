import AppKit
@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import StillLoopCore

final class MacLocalContextProvider: ContextProvider {
    private let cameraCapture = CameraStillCapture()

    func capture() async -> ContextSnapshot {
        let focusedWindow = bestFocusedWindow()
        let appName = focusedWindow.appName
        let windowTitle = focusedWindow.title
        let screenshot = captureCompressedScreenshot()
        let camera = await cameraCapture.capture()

        return ContextSnapshot(
            timestamp: Date(),
            activeAppName: appName,
            windowTitle: windowTitle,
            browserTitle: nil,
            browserURL: nil,
            screenshotAvailable: screenshot != nil,
            cameraFrameAvailable: camera != nil,
            screenshotPixelWidth: screenshot?.width,
            screenshotPixelHeight: screenshot?.height,
            screenshotCompressedBytes: screenshot?.compressedBytes,
            screenshotMimeType: screenshot?.mimeType,
            screenshotData: screenshot?.data,
            cameraPixelWidth: camera?.width,
            cameraPixelHeight: camera?.height,
            cameraCompressedBytes: camera?.compressedBytes,
            cameraMimeType: camera?.mimeType,
            cameraData: camera?.data
        )
    }

    private func bestFocusedWindow() -> (appName: String, title: String) {
        let frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return (frontmostApp, "当前窗口")
        }

        let visibleWindows = windows.compactMap { window -> (appName: String, title: String)? in
            guard
                let ownerName = window[kCGWindowOwnerName as String] as? String,
                let layer = window[kCGWindowLayer as String] as? Int,
                layer == 0
            else {
                return nil
            }
            let title = (window[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (ownerName, title?.isEmpty == false ? title! : "当前窗口")
        }

        if frontmostApp != "StillLoop" {
            return visibleWindows.first { $0.appName == frontmostApp } ?? (frontmostApp, "当前窗口")
        }

        return visibleWindows.first { $0.appName != "StillLoop" } ?? (frontmostApp, "StillLoop")
    }

    private func captureCompressedScreenshot() -> VisualCaptureSummary? {
        let displayID = CGMainDisplayID()
        guard let image = CGDisplayCreateImage(displayID) else { return nil }
        return compress(image: image, maxDimension: 512, quality: 0.42)
    }
}

private struct VisualCaptureSummary {
    var width: Int
    var height: Int
    var compressedBytes: Int
    var mimeType: String
    var data: Data
}

private func compress(image: CGImage, maxDimension: CGFloat, quality: CGFloat) -> VisualCaptureSummary? {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    let scale = min(1, maxDimension / max(width, height))
    let targetWidth = max(1, Int(width * scale))
    let targetHeight = max(1, Int(height * scale))

    guard
        let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        return nil
    }

    context.interpolationQuality = .low
    context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
    guard let scaled = context.makeImage() else { return nil }
    let representation = NSBitmapImageRep(cgImage: scaled)
    guard let data = representation.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
        return nil
    }
    return VisualCaptureSummary(width: targetWidth, height: targetHeight, compressedBytes: data.count, mimeType: "image/jpeg", data: data)
}

private final class CameraStillCapture: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<VisualCaptureSummary?, Never>?
    private var activeSession: AVCaptureSession?
    private var activeOutput: AVCapturePhotoOutput?

    func capture() async -> VisualCaptureSummary? {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            let session = AVCaptureSession()
            session.sessionPreset = .low

            guard
                let device = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else {
                continuation.resume(returning: nil)
                self.continuation = nil
                return
            }

            let output = AVCapturePhotoOutput()
            guard session.canAddOutput(output) else {
                continuation.resume(returning: nil)
                self.continuation = nil
                return
            }

            session.addInput(input)
            session.addOutput(output)
            self.activeSession = session
            self.activeOutput = output

            DispatchQueue.global(qos: .utility).async {
                session.startRunning()
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
                    self.finish(nil)
                }
            }
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard
            error == nil,
            let data = photo.fileDataRepresentation(),
            let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            finish(nil)
            return
        }

        finish(compress(image: image, maxDimension: 384, quality: 0.38))
    }

    private func finish(_ summary: VisualCaptureSummary?) {
        activeSession?.stopRunning()
        activeSession = nil
        activeOutput = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: summary)
    }
}
