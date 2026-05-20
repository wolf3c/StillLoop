import AppKit
import Foundation
import StillLoopCore

protocol FocusReturnTargetOpening {
    func open(_ target: FocusReturnTarget) -> Bool
}

protocol AppleScriptRunning {
    func run(_ source: String) -> Bool
}

struct NSAppleScriptRunner: AppleScriptRunning {
    func run(_ source: String) -> Bool {
        var error: NSDictionary?
        _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
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
            return scriptRunner.run(browserScript(for: target.appName, url: browserURL, kind: browserKind))
        }

        return openApplicationTarget(target)
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

    private func browserScript(for appName: String, url: String, kind: BrowserAutomationKind) -> String {
        switch kind {
        case .chromium:
            return chromiumBrowserScript(appName: appName, url: url)
        case .safari:
            return safariBrowserScript(appName: appName, url: url)
        }
    }

    private func chromiumBrowserScript(appName: String, url: String) -> String {
        let quotedAppName = appleScriptStringLiteral(appName)
        let quotedURL = appleScriptStringLiteral(url)
        return """
        tell application \(quotedAppName)
            repeat with windowIndex from 1 to count of windows
                repeat with tabIndex from 1 to count of tabs of window windowIndex
                    try
                        if URL of tab tabIndex of window windowIndex is \(quotedURL) then
                            set active tab index of window windowIndex to tabIndex
                            set index of window windowIndex to 1
                            activate
                            return "matched"
                        end if
                    end try
                end repeat
            end repeat
            open location \(quotedURL)
            activate
            return "opened"
        end tell
        """
    }

    private func safariBrowserScript(appName: String, url: String) -> String {
        let quotedAppName = appleScriptStringLiteral(appName)
        let quotedURL = appleScriptStringLiteral(url)
        return """
        tell application \(quotedAppName)
            repeat with windowIndex from 1 to count of windows
                repeat with tabIndex from 1 to count of tabs of window windowIndex
                    try
                        if URL of tab tabIndex of window windowIndex is \(quotedURL) then
                            set current tab of window windowIndex to tab tabIndex of window windowIndex
                            set index of window windowIndex to 1
                            activate
                            return "matched"
                        end if
                    end try
                end repeat
            end repeat
            open location \(quotedURL)
            activate
            return "opened"
        end tell
        """
    }
}
