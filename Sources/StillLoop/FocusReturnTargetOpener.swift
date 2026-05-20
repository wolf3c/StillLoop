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
        return NSWorkspace.shared.open(appURL)
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

struct MacFocusReturnTargetOpener: FocusReturnTargetOpening {
    private struct BrowserTabLocation: Equatable {
        var windowIndex: Int
        var tabIndex: Int
        var isActive: Bool
        var url: String
    }

    private let scriptRunner: AppleScriptRunning
    private let applicationOpener: FocusReturnTargetApplicationOpening

    init(
        scriptRunner: AppleScriptRunning = NSAppleScriptRunner(),
        applicationOpener: FocusReturnTargetApplicationOpening = WorkspaceFocusReturnTargetApplicationOpener()
    ) {
        self.scriptRunner = scriptRunner
        self.applicationOpener = applicationOpener
    }

    func open(_ target: FocusReturnTarget) -> Bool {
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
        if let bundleIdentifier = target.appBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleIdentifier.isEmpty {
            if applicationOpener.activateRunningApplication(bundleIdentifier: bundleIdentifier) {
                return true
            }
            if applicationOpener.openApplication(bundleIdentifier: bundleIdentifier) {
                return true
            }
        }

        return applicationOpener.activateRunningApplication(named: target.appName)
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
