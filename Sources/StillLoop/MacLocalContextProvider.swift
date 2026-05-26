import AppKit
@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import StillLoopCore

final class MacLocalContextProvider: ContextProvider {
    private let browserMetadataReader: BrowserTabMetadataReading
    private let focusedWindowReader: FocusedWindowReading
    private let visualCapture: VisualCapture
    private let browserAutomationNoticePresenter: any BrowserAutomationNoticePresenting

    init(
        browserMetadataReader: BrowserTabMetadataReading = AppleScriptBrowserTabMetadataReader(),
        focusedWindowReader: FocusedWindowReading = CGWindowFocusedWindowReader(),
        visualCapture: VisualCapture = SystemVisualCapture(),
        browserAutomationNoticePresenter: any BrowserAutomationNoticePresenting = NoBrowserAutomationNoticePresenter()
    ) {
        self.browserMetadataReader = browserMetadataReader
        self.focusedWindowReader = focusedWindowReader
        self.visualCapture = visualCapture
        self.browserAutomationNoticePresenter = browserAutomationNoticePresenter
    }

    func capture() async -> ContextSnapshot {
        let focusedWindow = focusedWindowReader.bestFocusedWindow()
        let appName = focusedWindow.appName
        let windowTitle = focusedWindow.title
        await browserAutomationNoticePresenter.presentBrowserAutomationNoticeIfNeeded(
            for: appName,
            bundleIdentifier: focusedWindow.bundleIdentifier
        )
        let browserMetadata = browserMetadataReader.currentTabMetadata(for: appName)
        let screenshot = visualCapture.captureCompressedScreenshot()
        let camera = await visualCapture.captureCameraStill()

        return ContextSnapshot(
            timestamp: Date(),
            activeAppName: appName,
            activeAppBundleIdentifier: focusedWindow.bundleIdentifier,
            windowTitle: windowTitle,
            browserTitle: browserMetadata?.title,
            browserURL: browserMetadata?.url,
            processIdentifier: focusedWindow.processIdentifier,
            windowNumber: focusedWindow.windowNumber,
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

protocol BrowserAutomationNoticePresenting {
    func presentBrowserAutomationNoticeIfNeeded(for appName: String, bundleIdentifier: String?) async
}

extension BrowserAutomationNoticePresenting {
    func presentBrowserAutomationNoticeIfNeeded(for appName: String) async {
        await presentBrowserAutomationNoticeIfNeeded(for: appName, bundleIdentifier: nil)
    }
}

struct NoBrowserAutomationNoticePresenter: BrowserAutomationNoticePresenting {
    func presentBrowserAutomationNoticeIfNeeded(for appName: String, bundleIdentifier: String?) async {}
}

struct FocusedWindow: Equatable {
    var appName: String
    var bundleIdentifier: String?
    var title: String
    var processIdentifier: Int? = nil
    var windowNumber: Int? = nil
    var spaceIdentifier: String? = nil
}

protocol FocusedWindowReading {
    func bestFocusedWindow() -> FocusedWindow
}

struct CGWindowFocusedWindowReader: FocusedWindowReading {
    func bestFocusedWindow() -> FocusedWindow {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let frontmostApp = frontmostApplication?.localizedName ?? "Unknown"
        let frontmostBundleIdentifier = frontmostApplication?.bundleIdentifier
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return FocusedWindow(appName: frontmostApp, bundleIdentifier: frontmostBundleIdentifier, title: "当前窗口")
        }

        let visibleWindows = Self.visibleWindows(from: windows)

        if !Self.isStillLoopAppName(frontmostApp) {
            if var focusedWindow = visibleWindows.first(where: { $0.appName == frontmostApp }) {
                focusedWindow.bundleIdentifier = focusedWindow.bundleIdentifier ?? frontmostBundleIdentifier
                focusedWindow.processIdentifier = focusedWindow.processIdentifier ?? frontmostApplication.map { Int($0.processIdentifier) }
                return focusedWindow
            }
            return FocusedWindow(
                appName: frontmostApp,
                bundleIdentifier: frontmostBundleIdentifier,
                title: "当前窗口",
                processIdentifier: frontmostApplication.map { Int($0.processIdentifier) },
                windowNumber: nil
            )
        }

        return visibleWindows.first { !Self.isStillLoopAppName($0.appName) } ?? FocusedWindow(
            appName: frontmostApp,
            bundleIdentifier: frontmostBundleIdentifier,
            title: "StillLoop",
            processIdentifier: frontmostApplication.map { Int($0.processIdentifier) },
            windowNumber: nil
        )
    }

    func rawFrontmostWindow() -> FocusedWindow {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let frontmostApp = frontmostApplication?.localizedName ?? "Unknown"
        let frontmostBundleIdentifier = frontmostApplication?.bundleIdentifier
        let frontmostProcessIdentifier = frontmostApplication.map { Int($0.processIdentifier) }
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return FocusedWindow(
                appName: frontmostApp,
                bundleIdentifier: frontmostBundleIdentifier,
                title: "当前窗口",
                processIdentifier: frontmostProcessIdentifier
            )
        }
        let visibleWindows = Self.visibleWindows(from: windows)
        if var focusedWindow = visibleWindows.first(where: { $0.processIdentifier == frontmostProcessIdentifier || $0.appName == frontmostApp }) {
            focusedWindow.bundleIdentifier = focusedWindow.bundleIdentifier ?? frontmostBundleIdentifier
            focusedWindow.processIdentifier = focusedWindow.processIdentifier ?? frontmostProcessIdentifier
            return focusedWindow
        }
        return FocusedWindow(
            appName: frontmostApp,
            bundleIdentifier: frontmostBundleIdentifier,
            title: "当前窗口",
            processIdentifier: frontmostProcessIdentifier,
            windowNumber: nil
        )
    }

    static func isStillLoopAppName(_ appName: String) -> Bool {
        appName == "StillLoop" || appName == "StillLoop Dev"
    }

    private static func visibleWindows(from windows: [[String: Any]]) -> [FocusedWindow] {
        windows.compactMap { window -> FocusedWindow? in
            guard
                let ownerName = window[kCGWindowOwnerName as String] as? String,
                let layer = window[kCGWindowLayer as String] as? Int,
                layer == 0
            else {
                return nil
            }
            let bundleIdentifier = Self.bundleIdentifier(for: window)
            let processIdentifier = Self.processIdentifier(for: window)
            let windowNumber = Self.windowNumber(for: window)
            let title = (window[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return FocusedWindow(
                appName: ownerName,
                bundleIdentifier: bundleIdentifier,
                title: title?.isEmpty == false ? title! : "当前窗口",
                processIdentifier: processIdentifier,
                windowNumber: windowNumber,
                spaceIdentifier: Self.spaceIdentifier(for: window)
            )
        }
    }

    private static func bundleIdentifier(for window: [String: Any]) -> String? {
        guard let processIdentifier = processIdentifier(for: window) else { return nil }
        return NSRunningApplication(processIdentifier: pid_t(processIdentifier))?.bundleIdentifier
    }

    private static func processIdentifier(for window: [String: Any]) -> Int? {
        let rawPID = window[kCGWindowOwnerPID as String]
        if let processIdentifier = rawPID as? pid_t {
            return Int(processIdentifier)
        }
        if let processIdentifier = rawPID as? Int {
            return processIdentifier
        }
        if let processIdentifier = rawPID as? NSNumber {
            return processIdentifier.intValue
        }
        return nil
    }

    private static func windowNumber(for window: [String: Any]) -> Int? {
        let rawWindowNumber = window[kCGWindowNumber as String]
        if let windowNumber = rawWindowNumber as? Int {
            return windowNumber
        }
        if let windowNumber = rawWindowNumber as? NSNumber {
            return windowNumber.intValue
        }
        return nil
    }

    private static func spaceIdentifier(for window: [String: Any]) -> String? {
        let rawSpace = window["kCGWindowWorkspace"] ?? window["Workspace"]
        if let space = rawSpace as? String {
            let trimmed = space.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let space = rawSpace as? Int {
            return String(space)
        }
        if let space = rawSpace as? NSNumber {
            return space.stringValue
        }
        return nil
    }
}

struct ActiveWorkTargetCapture: Equatable {
    var target: ActiveWorkTarget
    var screenshot: TaskRelevantTargetScreenshot?
}

protocol ActiveWorkTargetProviding {
    func currentActiveWorkTarget() async -> ActiveWorkTargetCapture?
}

struct MacActiveWorkTargetProvider: ActiveWorkTargetProviding {
    private let focusedWindowReader: CGWindowFocusedWindowReader
    private let browserMetadataReader: BrowserTabMetadataReading
    private let visualCapture: VisualCapture
    private let browserAutomationNoticePresenter: any BrowserAutomationNoticePresenting

    init(
        focusedWindowReader: CGWindowFocusedWindowReader = CGWindowFocusedWindowReader(),
        browserMetadataReader: BrowserTabMetadataReading = AppleScriptBrowserTabMetadataReader(),
        visualCapture: VisualCapture = SystemVisualCapture(),
        browserAutomationNoticePresenter: any BrowserAutomationNoticePresenting = NoBrowserAutomationNoticePresenter()
    ) {
        self.focusedWindowReader = focusedWindowReader
        self.browserMetadataReader = browserMetadataReader
        self.visualCapture = visualCapture
        self.browserAutomationNoticePresenter = browserAutomationNoticePresenter
    }

    func currentActiveWorkTarget() async -> ActiveWorkTargetCapture? {
        let focusedWindow = focusedWindowReader.rawFrontmostWindow()
        await browserAutomationNoticePresenter.presentBrowserAutomationNoticeIfNeeded(
            for: focusedWindow.appName,
            bundleIdentifier: focusedWindow.bundleIdentifier
        )
        let browserMetadata = browserMetadataReader.currentTabMetadata(for: focusedWindow.appName)
        let screenshot = visualCapture.captureCompressedScreenshot().map {
            TaskRelevantTargetScreenshot(
                width: $0.width,
                height: $0.height,
                compressedBytes: $0.compressedBytes,
                mimeType: $0.mimeType,
                data: $0.data
            )
        }
        return ActiveWorkTargetCapture(
            target: ActiveWorkTarget(
                appName: focusedWindow.appName,
                bundleIdentifier: focusedWindow.bundleIdentifier,
                processIdentifier: focusedWindow.processIdentifier,
                windowTitle: focusedWindow.title,
                browserTitle: browserMetadata?.title,
                browserURL: browserMetadata?.url,
                windowNumber: focusedWindow.windowNumber,
                spaceIdentifier: focusedWindow.spaceIdentifier
            ),
            screenshot: screenshot
        )
    }
}

struct BrowserTabMetadata: Equatable {
    var title: String
    var url: String
}

enum BrowserAutomationKind {
    case chromium
    case safari
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
        switch Self.automationKind(for: appName) {
        case .chromium:
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

        case .safari:
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

        case nil:
            return nil
        }
    }

    static func supportsMetadata(for appName: String) -> Bool {
        automationKind(for: appName) != nil
    }

    static func automationKind(for appName: String) -> BrowserAutomationKind? {
        if chromiumBrowserNames.contains(appName) {
            return .chromium
        }
        if safariBrowserNames.contains(appName) {
            return .safari
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

func appleScriptStringLiteral(_ value: String) -> String {
    "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
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

func compress(image: CGImage, maxDimension: Double, quality: Double) -> VisualCaptureSummary? {
    autoreleasepool {
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

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: max(0, min(1, quality))
        ]
        CGImageDestinationAddImage(destination, scaled, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        let encoded = data as Data
        return VisualCaptureSummary(width: targetWidth, height: targetHeight, compressedBytes: encoded.count, mimeType: "image/jpeg", data: encoded)
    }
}

struct CameraStillCaptureTiming: Equatable {
    var warmUpDelay: TimeInterval
    var photoTimeout: TimeInterval

    static let standard = CameraStillCaptureTiming(warmUpDelay: 1.0, photoTimeout: 3.0)
}

protocol CameraStillCaptureScheduling {
    func async(_ work: @escaping () -> Void)
    func asyncAfter(seconds: TimeInterval, _ work: @escaping () -> Void)
}

struct DispatchQueueCameraStillCaptureScheduler: CameraStillCaptureScheduling {
    func async(_ work: @escaping () -> Void) {
        DispatchQueue.global(qos: .utility).async(execute: work)
    }

    func asyncAfter(seconds: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

struct CameraStillCaptureSchedule {
    var timing: CameraStillCaptureTiming
    var scheduler: any CameraStillCaptureScheduling

    init(
        timing: CameraStillCaptureTiming = .standard,
        scheduler: any CameraStillCaptureScheduling = DispatchQueueCameraStillCaptureScheduler()
    ) {
        self.timing = timing
        self.scheduler = scheduler
    }

    func capture(
        startRunning: @escaping () -> Void,
        capturePhoto: @escaping () -> Void,
        timeout: @escaping () -> Void
    ) {
        scheduler.async {
            startRunning()
            scheduler.asyncAfter(seconds: timing.warmUpDelay) {
                capturePhoto()
                scheduler.asyncAfter(seconds: timing.photoTimeout, timeout)
            }
        }
    }
}

final class CameraStillCaptureFinishGate: @unchecked Sendable {
    private let lock = NSLock()
    private var hasFinished = false

    func finish(_ work: () -> Void) {
        lock.lock()
        guard !hasFinished else {
            lock.unlock()
            return
        }
        hasFinished = true
        lock.unlock()
        work()
    }
}

private final class CameraStillCapture: @unchecked Sendable {
    private let captureSchedule: CameraStillCaptureSchedule

    init(captureSchedule: CameraStillCaptureSchedule = CameraStillCaptureSchedule()) {
        self.captureSchedule = captureSchedule
    }

    func capture() async -> VisualCaptureSummary? {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            return nil
        }

        let request = CameraStillCaptureRequest(captureSchedule: captureSchedule)
        return await request.capture()
    }
}

private final class CameraStillCaptureRequest: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<VisualCaptureSummary?, Never>?
    private var activeSession: AVCaptureSession?
    private var activeOutput: AVCapturePhotoOutput?
    private let captureSchedule: CameraStillCaptureSchedule
    private let finishGate = CameraStillCaptureFinishGate()

    init(captureSchedule: CameraStillCaptureSchedule = CameraStillCaptureSchedule()) {
        self.captureSchedule = captureSchedule
    }

    func capture() async -> VisualCaptureSummary? {
        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            let session = AVCaptureSession()
            session.sessionPreset = .low

            guard
                let device = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else {
                finish(nil)
                return
            }

            let output = AVCapturePhotoOutput()
            guard session.canAddOutput(output) else {
                finish(nil)
                return
            }

            session.addInput(input)
            session.addOutput(output)
            self.activeSession = session
            self.activeOutput = output

            captureSchedule.capture(
                startRunning: {
                    session.startRunning()
                },
                capturePhoto: {
                    output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
                },
                timeout: {
                    self.finish(nil)
                }
            )
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
        finishGate.finish {
            let session = activeSession
            let continuation = continuation
            activeSession = nil
            activeOutput = nil
            self.continuation = nil
            session?.stopRunning()
            continuation?.resume(returning: summary)
        }
    }
}
