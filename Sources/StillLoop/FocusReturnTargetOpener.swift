import ApplicationServices
import AppKit
import Foundation
import StillLoopCore

protocol FocusReturnTargetOpening {
    func open(_ target: FocusReturnTarget) -> Bool
}

struct AppleScriptRunResult: Equatable {
    var output: String
    var succeeded: Bool

    static func success(output: String = "") -> AppleScriptRunResult {
        AppleScriptRunResult(output: output, succeeded: true)
    }

    static let failure = AppleScriptRunResult(output: "", succeeded: false)
}

protocol AppleScriptRunning {
    func run(_ source: String) -> AppleScriptRunResult
}

struct NSAppleScriptRunner: AppleScriptRunning {
    func run(_ source: String) -> AppleScriptRunResult {
        var error: NSDictionary?
        guard let output = NSAppleScript(source: source)?.executeAndReturnError(&error),
              error == nil
        else {
            return .failure
        }
        return .success(output: output.stringValue ?? "")
    }
}

protocol FocusReturnTargetApplicationOpening {
    func activateRunningApplication(bundleIdentifier: String) -> Bool
    func openApplication(bundleIdentifier: String) -> Bool
    func activateRunningApplication(named appName: String) -> Bool
}

protocol FocusReturnTargetWindowRaising {
    func raiseWindow(for target: FocusReturnTarget) -> Bool
}

struct WorkspaceFocusReturnTargetApplicationOpener: FocusReturnTargetApplicationOpening {
    func activateRunningApplication(bundleIdentifier: String) -> Bool {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first?
            .activate(options: [.activateAllWindows, .activateIgnoringOtherApps]) == true
    }

    func openApplication(bundleIdentifier: String) -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        return true
    }

    func activateRunningApplication(named appName: String) -> Bool {
        NSWorkspace.shared.runningApplications
            .first { application in
                application.localizedName?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(appName.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
            }?
            .activate(options: [.activateAllWindows, .activateIgnoringOtherApps]) == true
    }
}

struct AccessibilityFocusReturnTargetWindowRaiser: FocusReturnTargetWindowRaising {
    private struct LiveWindow {
        var title: String?
        var bounds: CGRect?
    }

    func raiseWindow(for target: FocusReturnTarget) -> Bool {
        guard let processIdentifier = target.processIdentifier,
              let windowNumber = target.windowNumber,
              let liveWindow = liveWindow(processIdentifier: processIdentifier, windowNumber: windowNumber),
              bundleMatches(target.appBundleIdentifier, processIdentifier: processIdentifier)
        else {
            return false
        }

        let application = AXUIElementCreateApplication(pid_t(processIdentifier))
        guard let axWindows = axWindows(for: application),
              let axWindow = bestAXWindow(in: axWindows, target: target, liveWindow: liveWindow)
        else {
            return false
        }

        _ = AXUIElementSetAttributeValue(application, kAXFocusedWindowAttribute as CFString, axWindow)
        let raiseResult = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        _ = NSRunningApplication(processIdentifier: pid_t(processIdentifier))?
            .activate(options: [.activateIgnoringOtherApps])
        return raiseResult == .success
    }

    private func bundleMatches(_ bundleIdentifier: String?, processIdentifier: Int) -> Bool {
        guard let bundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty
        else {
            return true
        }
        return NSRunningApplication(processIdentifier: pid_t(processIdentifier))?.bundleIdentifier == bundleIdentifier
    }

    private func liveWindow(processIdentifier: Int, windowNumber: Int) -> LiveWindow? {
        guard let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        else {
            return nil
        }
        guard let window = windows.first(where: { window in
            Self.intValue(window[kCGWindowOwnerPID as String]) == processIdentifier
                && Self.intValue(window[kCGWindowNumber as String]) == windowNumber
                && Self.intValue(window[kCGWindowLayer as String]) == 0
        }) else {
            return nil
        }
        let title = (window[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bounds: CGRect?
        if let boundsDictionary = window[kCGWindowBounds as String] as? [String: Any] {
            bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
        } else {
            bounds = nil
        }
        return LiveWindow(title: title?.isEmpty == false ? title : nil, bounds: bounds)
    }

    private func axWindows(for application: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private func bestAXWindow(
        in windows: [AXUIElement],
        target: FocusReturnTarget,
        liveWindow: LiveWindow
    ) -> AXUIElement? {
        windows.first { axWindow in
            titleMatches(axWindow, target: target, liveWindow: liveWindow)
                && frameMatches(axWindow, liveWindow: liveWindow)
        }
            ?? windows.first { frameMatches($0, liveWindow: liveWindow) }
            ?? windows.first { titleMatches($0, target: target, liveWindow: liveWindow) }
    }

    private func titleMatches(_ axWindow: AXUIElement, target: FocusReturnTarget, liveWindow: LiveWindow) -> Bool {
        let axTitle = normalized(title(for: axWindow))
        guard !axTitle.isEmpty else { return false }
        return [target.windowTitle, liveWindow.title]
            .map(normalized)
            .contains(axTitle)
    }

    private func frameMatches(_ axWindow: AXUIElement, liveWindow: LiveWindow) -> Bool {
        guard let liveBounds = liveWindow.bounds, let axFrame = frame(for: axWindow) else {
            return false
        }
        return abs(axFrame.origin.x - liveBounds.origin.x) <= 2
            && abs(axFrame.origin.y - liveBounds.origin.y) <= 2
            && abs(axFrame.size.width - liveBounds.size.width) <= 2
            && abs(axFrame.size.height - liveBounds.size.height) <= 2
    }

    private func title(for axWindow: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func frame(for axWindow: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let positionAXValue = positionValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &point),
              AXValueGetValue(sizeAXValue, .cgSize, &size)
        else {
            return nil
        }
        return CGRect(origin: point, size: size)
    }

    private func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        if let value = value as? pid_t {
            return Int(value)
        }
        return nil
    }
}

struct MacFocusReturnTargetOpener: FocusReturnTargetOpening {
    private struct BrowserTabLocation: Equatable {
        var windowIndex: Int
        var tabIndex: Int
        var isActive: Bool
        var url: String
    }

    private let scriptRunner: AppleScriptRunning
    private let applicationOpener: FocusReturnTargetApplicationOpening
    private let windowRaiser: FocusReturnTargetWindowRaising

    init(
        scriptRunner: AppleScriptRunning = NSAppleScriptRunner(),
        applicationOpener: FocusReturnTargetApplicationOpening = WorkspaceFocusReturnTargetApplicationOpener(),
        windowRaiser: FocusReturnTargetWindowRaising = AccessibilityFocusReturnTargetWindowRaiser()
    ) {
        self.scriptRunner = scriptRunner
        self.applicationOpener = applicationOpener
        self.windowRaiser = windowRaiser
    }

    func open(_ target: FocusReturnTarget) -> Bool {
        guard target.isEligibleReturnTarget else { return false }
        if let browserURL = target.browserURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !browserURL.isEmpty,
           let browserKind = AppleScriptBrowserTabMetadataReader.automationKind(for: target.appName) {
            return openBrowserTarget(target, url: browserURL, kind: browserKind)
        }

        return openApplicationTarget(target)
    }

    private func openBrowserTarget(_ target: FocusReturnTarget, url: String, kind: BrowserAutomationKind) -> Bool {
        let inventoryResult = scriptRunner.run(browserInventoryScript(for: target.appName, kind: kind))
        guard inventoryResult.succeeded else { return false }

        let tabs = browserTabLocations(from: inventoryResult.output)
        if let match = browserTabMatch(in: tabs, targetURL: url) {
            let selectionResult = scriptRunner.run(browserSelectionScript(
                for: target.appName,
                location: match,
                kind: kind
            ))
            guard scriptResult(selectionResult, hasOutput: "selected") else { return false }
            activateBrowserApplication(target)
            return true
        }

        let openResult = scriptRunner.run(browserOpenURLScript(for: target.appName, url: url))
        guard scriptResult(openResult, hasOutput: "opened") else { return false }
        activateBrowserApplication(target)
        return true
    }

    private func openApplicationTarget(_ target: FocusReturnTarget) -> Bool {
        if windowRaiser.raiseWindow(for: target) {
            return true
        }

        if let bundleIdentifier = target.appBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleIdentifier.isEmpty {
            if applicationOpener.activateRunningApplication(bundleIdentifier: bundleIdentifier) {
                if !hasSpecificWindowTarget(target) {
                    _ = applicationOpener.openApplication(bundleIdentifier: bundleIdentifier)
                }
                return true
            }
            if applicationOpener.openApplication(bundleIdentifier: bundleIdentifier) {
                return true
            }
        }

        return applicationOpener.activateRunningApplication(named: target.appName)
    }

    private func hasSpecificWindowTarget(_ target: FocusReturnTarget) -> Bool {
        guard target.processIdentifier != nil,
              target.windowNumber != nil,
              target.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            return false
        }
        return true
    }

    @discardableResult
    private func activateBrowserApplication(_ target: FocusReturnTarget) -> Bool {
        if let bundleIdentifier = target.appBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleIdentifier.isEmpty {
            return applicationOpener.activateRunningApplication(bundleIdentifier: bundleIdentifier)
        }
        return applicationOpener.activateRunningApplication(named: target.appName)
    }

    private func browserInventoryScript(for appName: String, kind: BrowserAutomationKind) -> String {
        switch kind {
        case .chromium:
            return chromiumBrowserInventoryScript(appName: appName)
        case .safari:
            return safariBrowserInventoryScript(appName: appName)
        }
    }

    private func browserSelectionScript(
        for appName: String,
        location: BrowserTabLocation,
        kind: BrowserAutomationKind
    ) -> String {
        switch kind {
        case .chromium:
            return chromiumBrowserSelectionScript(appName: appName, location: location)
        case .safari:
            return safariBrowserSelectionScript(appName: appName, location: location)
        }
    }

    private func browserOpenURLScript(for appName: String, url: String) -> String {
        let quotedAppName = appleScriptStringLiteral(appName)
        let quotedURL = appleScriptStringLiteral(url)
        return """
        tell application \(quotedAppName)
            open location \(quotedURL)
            activate
            return "opened"
        end tell
        """
    }

    private func chromiumBrowserInventoryScript(appName: String) -> String {
        let quotedAppName = appleScriptStringLiteral(appName)
        return """
        tell application \(quotedAppName)
            if (count of windows) is 0 then return ""
            set output to ""
            set delimiter to ASCII character 9
            repeat with windowIndex from 1 to count of windows
                set activeIndex to 0
                try
                    set activeIndex to active tab index of window windowIndex
                end try
                repeat with tabIndex from 1 to count of tabs of window windowIndex
                    set tabURL to ""
                    set activeFlag to "0"
                    try
                        set tabURL to URL of tab tabIndex of window windowIndex
                    end try
                    if windowIndex is 1 and tabIndex is activeIndex then
                        set activeFlag to "1"
                    end if
                    if output is not "" then
                        set output to output & linefeed
                    end if
                    set output to output & (windowIndex as text) & delimiter & (tabIndex as text) & delimiter & activeFlag & delimiter & tabURL
                end repeat
            end repeat
            return output
        end tell
        """
    }

    private func chromiumBrowserSelectionScript(appName: String, location: BrowserTabLocation) -> String {
        let quotedAppName = appleScriptStringLiteral(appName)
        return """
        tell application \(quotedAppName)
            try
                set active tab index of window \(location.windowIndex) to \(location.tabIndex)
                set index of window \(location.windowIndex) to 1
                activate
                return "selected"
            on error
                return "missing"
            end try
        end tell
        """
    }

    private func safariBrowserInventoryScript(appName: String) -> String {
        let quotedAppName = appleScriptStringLiteral(appName)
        return """
        tell application \(quotedAppName)
            if (count of windows) is 0 then return ""
            set output to ""
            set delimiter to ASCII character 9
            repeat with windowIndex from 1 to count of windows
                repeat with tabIndex from 1 to count of tabs of window windowIndex
                    set tabURL to ""
                    set activeFlag to "0"
                    try
                        set tabURL to URL of tab tabIndex of window windowIndex
                    end try
                    try
                        if windowIndex is 1 and tab tabIndex of window windowIndex is current tab of window windowIndex then
                            set activeFlag to "1"
                        end if
                    end try
                    if output is not "" then
                        set output to output & linefeed
                    end if
                    set output to output & (windowIndex as text) & delimiter & (tabIndex as text) & delimiter & activeFlag & delimiter & tabURL
                end repeat
            end repeat
            return output
        end tell
        """
    }

    private func safariBrowserSelectionScript(appName: String, location: BrowserTabLocation) -> String {
        let quotedAppName = appleScriptStringLiteral(appName)
        return """
        tell application \(quotedAppName)
            try
                set current tab of window \(location.windowIndex) to tab \(location.tabIndex) of window \(location.windowIndex)
                set index of window \(location.windowIndex) to 1
                activate
                return "selected"
            on error
                return "missing"
            end try
        end tell
        """
    }

    private func browserTabLocations(from output: String) -> [BrowserTabLocation] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
                guard parts.count == 4,
                      let windowIndex = Int(parts[0]),
                      let tabIndex = Int(parts[1]),
                      windowIndex > 0,
                      tabIndex > 0
                else {
                    return nil
                }
                return BrowserTabLocation(
                    windowIndex: windowIndex,
                    tabIndex: tabIndex,
                    isActive: parts[2] == "1",
                    url: String(parts[3]).trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
    }

    private func browserTabMatch(in tabs: [BrowserTabLocation], targetURL: String) -> BrowserTabLocation? {
        let comparableTargetURL = targetURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetHost = comparableHost(for: comparableTargetURL)

        func isExactMatch(_ tab: BrowserTabLocation) -> Bool {
            tab.url.trimmingCharacters(in: .whitespacesAndNewlines) == comparableTargetURL
        }

        func isHostMatch(_ tab: BrowserTabLocation) -> Bool {
            guard let targetHost else { return false }
            return comparableHost(for: tab.url) == targetHost
        }

        if let activeMatch = tabs.first(where: { $0.isActive && (isExactMatch($0) || isHostMatch($0)) }) {
            return activeMatch
        }
        if let exactMatch = tabs.first(where: isExactMatch) {
            return exactMatch
        }
        return tabs.first(where: isHostMatch)
    }

    private func comparableHost(for url: String) -> String? {
        guard let host = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines))?
            .host?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !host.isEmpty
        else {
            return nil
        }
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }

    private func scriptResult(_ result: AppleScriptRunResult, hasOutput expectedOutput: String) -> Bool {
        result.succeeded && result.output.trimmingCharacters(in: .whitespacesAndNewlines) == expectedOutput
    }
}
