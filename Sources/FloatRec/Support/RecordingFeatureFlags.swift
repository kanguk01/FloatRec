import Foundation

struct RecordingFeatureFlags {
    private static let autoZoomKey = "featureFlags.isAutoZoomEnabled"
    private static let clickHighlightKey = "featureFlags.isClickHighlightEnabled"
    private static let cameraStyleKey = "featureFlags.cameraControlStyle"
    private static let spotlightKey = "featureFlags.defaultManualSpotlightEnabled"

    var isAutoZoomEnabled: Bool {
        didSet { UserDefaults.standard.set(isAutoZoomEnabled, forKey: Self.autoZoomKey) }
    }

    var isClickHighlightEnabled: Bool {
        didSet { UserDefaults.standard.set(isClickHighlightEnabled, forKey: Self.clickHighlightKey) }
    }

    var cameraControlStyle: CameraControlStyle {
        didSet { UserDefaults.standard.set(cameraControlStyle.rawValue, forKey: Self.cameraStyleKey) }
    }

    var defaultManualSpotlightEnabled: Bool {
        didSet { UserDefaults.standard.set(defaultManualSpotlightEnabled, forKey: Self.spotlightKey) }
    }

    static let synchronousPostProcessingDuration: TimeInterval = 5
    static let maxBackgroundPostProcessingDuration: TimeInterval = 90

    init() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: Self.autoZoomKey) != nil {
            isAutoZoomEnabled = defaults.bool(forKey: Self.autoZoomKey)
        } else {
            isAutoZoomEnabled = true
        }

        if defaults.object(forKey: Self.clickHighlightKey) != nil {
            isClickHighlightEnabled = defaults.bool(forKey: Self.clickHighlightKey)
        } else {
            isClickHighlightEnabled = true
        }

        if let rawStyle = defaults.string(forKey: Self.cameraStyleKey),
           let style = CameraControlStyle(rawValue: rawStyle) {
            cameraControlStyle = style
        } else {
            cameraControlStyle = .automatic
        }

        if defaults.object(forKey: Self.spotlightKey) != nil {
            defaultManualSpotlightEnabled = defaults.bool(forKey: Self.spotlightKey)
        } else {
            defaultManualSpotlightEnabled = true
        }
    }
}
