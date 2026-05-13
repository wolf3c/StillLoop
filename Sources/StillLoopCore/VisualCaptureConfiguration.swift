import Foundation

public struct VisualCaptureConfiguration: Equatable {
    public struct Channel: Equatable {
        public var maxDimension: Double
        public var jpegQuality: Double

        public init(maxDimension: Double, jpegQuality: Double) {
            self.maxDimension = maxDimension
            self.jpegQuality = jpegQuality
        }
    }

    public var screenshot: Channel
    public var camera: Channel

    public init(screenshot: Channel, camera: Channel) {
        self.screenshot = screenshot
        self.camera = camera
    }

    public static let standard = VisualCaptureConfiguration(
        screenshot: .init(maxDimension: 1024, jpegQuality: 0.60),
        camera: .init(maxDimension: 512, jpegQuality: 0.50)
    )
}
