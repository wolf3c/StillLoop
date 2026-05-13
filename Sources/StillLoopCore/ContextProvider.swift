import Foundation

public protocol ContextProvider {
    func capture() async -> ContextSnapshot
}

public final class MockContextProvider: ContextProvider {
    private var index = 0
    private let task: () -> String

    public init(task: @escaping () -> String) {
        self.task = task
    }

    public func capture() async -> ContextSnapshot {
        let samples = makeSamples(task: task())
        let sample = samples[index % samples.count]
        index += 1
        return sample
    }

    private func makeSamples(task: String) -> [ContextSnapshot] {
        [
            ContextSnapshot(
                timestamp: Date(),
                activeAppName: "Xcode",
                windowTitle: task.isEmpty ? "StillLoop" : task,
                browserTitle: nil,
                browserURL: nil,
                screenshotAvailable: true,
                cameraFrameAvailable: false
            ),
            ContextSnapshot(
                timestamp: Date(),
                activeAppName: "Safari",
                windowTitle: "SwiftUI documentation",
                browserTitle: "Apple Developer",
                browserURL: "https://developer.apple.com/documentation/swiftui",
                screenshotAvailable: true,
                cameraFrameAvailable: true
            ),
            ContextSnapshot(
                timestamp: Date(),
                activeAppName: "YouTube",
                windowTitle: "Recommended videos",
                browserTitle: "Music videos",
                browserURL: "https://youtube.com",
                screenshotAvailable: true,
                cameraFrameAvailable: true
            )
        ]
    }
}
