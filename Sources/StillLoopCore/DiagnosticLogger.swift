import Foundation

public enum DiagnosticLogValue: Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
}

public protocol DiagnosticLogging: AnyObject {
    var fileURL: URL? { get }
    func record(_ event: String, fields: [String: DiagnosticLogValue])
}

public final class NoopDiagnosticLogger: DiagnosticLogging {
    public let fileURL: URL? = nil

    public init() {}

    public func record(_ event: String, fields: [String: DiagnosticLogValue]) {}
}

public final class FileDiagnosticLogger: DiagnosticLogging {
    public let fileURL: URL?

    private let lock = NSLock()
    private let dateFormatter: ISO8601DateFormatter
    private let fileManager: FileManager

    public init(appSupportDirectory: URL, fileManager: FileManager = .default) {
        self.fileURL = appSupportDirectory
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("stillloop-dev.log")
        self.fileManager = fileManager
        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    public func record(_ event: String, fields: [String: DiagnosticLogValue] = [:]) {
        guard let fileURL else { return }
        var payload: [String: Any] = [
            "timestamp": dateFormatter.string(from: Date()),
            "event": event
        ]
        for (key, value) in fields {
            payload[key] = value.jsonValue
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8)
        else { return }

        lock.lock()
        defer { lock.unlock() }
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let data = (line + "\n").data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } else {
                try (line + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            // Diagnostic logging must never affect focus evaluation.
        }
    }
}

private extension DiagnosticLogValue {
    var jsonValue: Any {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .bool(let value):
            return value
        }
    }
}
