import Foundation

struct RecordingFeatureFlags {
    var isAutoZoomEnabled = true
    var isClickHighlightEnabled = true
    var cameraControlStyle: CameraControlStyle = .automatic
    var defaultManualSpotlightEnabled = true

    static let synchronousPostProcessingDuration: TimeInterval = 5
    static let maxBackgroundPostProcessingDuration: TimeInterval = 90
}
