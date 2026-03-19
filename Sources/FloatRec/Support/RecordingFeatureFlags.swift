import Foundation

struct RecordingFeatureFlags {
    private static let autoZoomKey = "featureFlags.isAutoZoomEnabled"
    private static let clickHighlightKey = "featureFlags.isClickHighlightEnabled"
    private static let cameraStyleKey = "featureFlags.cameraControlStyle"
    private static let spotlightKey = "featureFlags.defaultManualSpotlightEnabled"
    private static let autoSavePathKey = "featureFlags.autoSavePath"
    private static let systemAudioKey = "featureFlags.isSystemAudioEnabled"
    private static let microphoneKey = "featureFlags.isMicrophoneEnabled"

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

    var isSystemAudioEnabled: Bool {
        didSet { UserDefaults.standard.set(isSystemAudioEnabled, forKey: Self.systemAudioKey) }
    }

    var isMicrophoneEnabled: Bool {
        didSet { UserDefaults.standard.set(isMicrophoneEnabled, forKey: Self.microphoneKey) }
    }

    var autoSavePath: String? {
        didSet {
            if let autoSavePath {
                UserDefaults.standard.set(autoSavePath, forKey: Self.autoSavePathKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.autoSavePathKey)
            }
        }
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
            cameraControlStyle = .manualHotkeys
        }

        if defaults.object(forKey: Self.spotlightKey) != nil {
            defaultManualSpotlightEnabled = defaults.bool(forKey: Self.spotlightKey)
        } else {
            defaultManualSpotlightEnabled = true
        }

        if defaults.object(forKey: Self.systemAudioKey) != nil {
            isSystemAudioEnabled = defaults.bool(forKey: Self.systemAudioKey)
        } else {
            isSystemAudioEnabled = false
        }

        if defaults.object(forKey: Self.microphoneKey) != nil {
            isMicrophoneEnabled = defaults.bool(forKey: Self.microphoneKey)
        } else {
            isMicrophoneEnabled = false
        }

        autoSavePath = defaults.string(forKey: Self.autoSavePathKey)
    }
}
