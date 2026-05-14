import AppKit
@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import StillLoopCore

final class MacLocalContextProvider: ContextProvider {
    private let browserMetadataReader: BrowserTabMetadataReading
    private let focusedWindowReader: FocusedWindowReading
    private let visualCapture: VisualCapture

    init(
        browserMetadataReader: BrowserTabMetadataReading = AppleScriptBrowserTabMetadataReader(),
        focusedWindowReader: FocusedWindowReading = CGWindowFocusedWindowReader(),
        visualCapture: VisualCapture = SystemVisualCapture()
    ) {
        self.browserMetadataReader = browserMetadataReader
        self.focusedWindowReader = focusedWindowReader
        self.visualCapture = visualCapture
    }

    func capture() async -> ContextSnapshot {
        let focusedWindow = focusedWindowReader.bestFocusedWindow()
        let appName = focusedWindow.appName
        let windowTitle = focusedWindow.title
        let browserMetadata = browserMetadataReader.currentTabMetadata(for: appName)
        let screenshot = visualCapture.captureCompressedScreenshot()
        let camera = await visualCapture.captureCameraStill()

        return ContextSnapshot(
            timestamp: Date(),
            activeAppName: appName,
            windowTitle: windowTitle,
            browserTitle: browserMetadata?.title,
            browserURL: browserMetadata?.url,
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
}

struct FocusedWindow: Equatable {
    var appName: String
    var title: String
}

protocol FocusedWindowReading {
    func bestFocusedWindow() -> FocusedWindow
}

struct CGWindowFocusedWindowReader: FocusedWindowReading {
    func bestFocusedWindow() -> FocusedWindow {
        let frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return FocusedWindow(appName: frontmostApp, title: "当前窗口")
        }

        let visibleWindows = windows.compactMap { window -> FocusedWindow? in
            guard
                let ownerName = window[kCGWindowOwnerName as String] as? String,
                let layer = window[kCGWindowLayer as String] as? Int,
                layer == 0
            else {
                return nil
            }
            let title = (window[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return FocusedWindow(appName: ownerName, title: title?.isEmpty == false ? title! : "当前窗口")
        }

        if frontmostApp != "StillLoop" {
            return visibleWindows.first { $0.appName == frontmostApp } ?? FocusedWindow(appName: frontmostApp, title: "当前窗口")
        }

        return visibleWindows.first { $0.appName != "StillLoop" } ?? FocusedWindow(appName: frontmostApp, title: "StillLoop")
    }
}

struct BrowserTabMetadata: Equatable {
    var title: String
    var url: String
}

protocol BrowserTabMetadataReading {
    func currentTabMetadata(for appName: String) -> BrowserTabMetadata?
}

struct AppleScriptBrowserTabMetadataReader: BrowserTabMetadataReading {
    func currentTabMetadata(for appName: String) -> BrowserTabMetadata? {
        guard let script = script(for: appName) else { return nil }
        var error: NSDictionary?
        let output = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue
        guard error == nil else { return nil }
        return metadata(from: output)
    }

    private func script(for appName: String) -> String? {
        let quotedAppName = appleScriptStringLiteral(appName)
        if Self.chromiumBrowserNames.contains(appName) {
            return """
            tell application \(quotedAppName)
                if (count of windows) is 0 then return ""
                set pageTitle to ""
                set pageURL to ""
                try
                    set pageTitle to title of active tab of front window
                end try
                try
                    set pageURL to URL of active tab of front window
                end try
                return pageTitle & linefeed & pageURL
            end tell
            """
        }

        if Self.safariBrowserNames.contains(appName) {
            return """
            tell application \(quotedAppName)
                if (count of documents) is 0 then return ""
                set pageTitle to ""
                set pageURL to ""
                try
                    set pageTitle to name of front document
                end try
                try
                    set pageURL to URL of front document
                end try
                return pageTitle & linefeed & pageURL
            end tell
            """
        }

        return nil
    }

    private func metadata(from output: String?) -> BrowserTabMetadata? {
        guard let output else { return nil }
        let lines = output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard lines.count >= 2 else { return nil }
        let title = lines[0]
        let url = lines[1]
        guard !title.isEmpty || !url.isEmpty else { return nil }
        return BrowserTabMetadata(title: title, url: url)
    }

    private func appleScriptStringLiteral(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static let chromiumBrowserNames: Set<String> = [
        "Google Chrome",
        "Google Chrome Canary",
        "Chromium",
        "Microsoft Edge",
        "Brave Browser",
        "Arc"
    ]

    private static let safariBrowserNames: Set<String> = [
        "Safari",
        "Safari Technology Preview"
    ]
}

protocol VisualCapture {
    func captureCompressedScreenshot() -> VisualCaptureSummary?
    func captureCameraStill() async -> VisualCaptureSummary?
}

struct SystemVisualCapture: VisualCapture {
    private let cameraCapture = CameraStillCapture()
    private let visualConfiguration = VisualCaptureConfiguration.standard

    func captureCompressedScreenshot() -> VisualCaptureSummary? {
        let displayID = CGMainDisplayID()
        guard let image = CGDisplayCreateImage(displayID) else { return nil }
        return compress(
            image: image,
            maxDimension: visualConfiguration.screenshot.maxDimension,
            quality: visualConfiguration.screenshot.jpegQuality
        )
    }

    func captureCameraStill() async -> VisualCaptureSummary? {
        await cameraCapture.capture()
    }
}

struct VisualCaptureSummary {
    var width: Int
    var height: Int
    var compressedBytes: Int
    var mimeType: String
    var data: Data
}

private func compress(image: CGImage, maxDimension: Double, quality: Double) -> VisualCaptureSummary? {
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    let scale = min(1, CGFloat(maxDimension) / max(width, height))
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

    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
    guard let scaled = context.makeImage() else { return nil }
    let representation = NSBitmapImageRep(cgImage: scaled)
    guard let data = representation.representation(using: .jpeg, properties: [.compressionFactor: CGFloat(quality)]) else {
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

        let cameraConfiguration = VisualCaptureConfiguration.standard.camera
        finish(compress(
            image: image,
            maxDimension: cameraConfiguration.maxDimension,
            quality: cameraConfiguration.jpegQuality
        ))
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
