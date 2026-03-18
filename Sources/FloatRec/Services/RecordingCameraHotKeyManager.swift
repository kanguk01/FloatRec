import Carbon
import Foundation

enum RecordingCameraHotKeyAction: UInt32, CaseIterable {
    case stepZoom = 1
    case toggleFollow = 2
    case resetOverview = 3
    case toggleSpotlightEffect = 4

    var title: String {
        switch self {
        case .stepZoom:
            "현재 위치 확대"
        case .toggleFollow:
            "커서 따라가기 토글"
        case .resetOverview:
            "전체 화면 복귀"
        case .toggleSpotlightEffect:
            "스포트라이트 토글"
        }
    }

    var displayString: String {
        switch self {
        case .stepZoom:
            "⌃1"
        case .toggleFollow:
            "⌃2"
        case .resetOverview:
            "⌃3"
        case .toggleSpotlightEffect:
            "⌃4"
        }
    }

    fileprivate var keyCode: UInt32 {
        switch self {
        case .stepZoom:
            UInt32(kVK_ANSI_1)
        case .toggleFollow:
            UInt32(kVK_ANSI_2)
        case .resetOverview:
            UInt32(kVK_ANSI_3)
        case .toggleSpotlightEffect:
            UInt32(kVK_ANSI_4)
        }
    }
}

final class RecordingCameraHotKeyManager {
    private static let hotKeySignature = OSType(0x46524343)

    var onAction: ((RecordingCameraHotKeyAction) -> Void)?

    private var hotKeyRefs: [RecordingCameraHotKeyAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    func register() {
        if eventHandler == nil {
            installHandler()
        }

        guard hotKeyRefs.isEmpty else {
            return
        }

        for action in RecordingCameraHotKeyAction.allCases {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: action.rawValue)
            RegisterEventHotKey(
                action.keyCode,
                UInt32(controlKey),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )

            if let hotKeyRef {
                hotKeyRefs[action] = hotKeyRef
            }
        }
    }

    func unregister() {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
    }

    deinit {
        unregister()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr,
                      hotKeyID.signature == RecordingCameraHotKeyManager.hotKeySignature,
                      let action = RecordingCameraHotKeyAction(rawValue: hotKeyID.id) else {
                    return OSStatus(eventNotHandledErr)
                }

                let manager = Unmanaged<RecordingCameraHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.onAction?(action)
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }
}
