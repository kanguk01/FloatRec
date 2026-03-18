import Carbon
import Foundation

enum GlobalHotKeyAction: UInt32, CaseIterable {
    case toggleRecording = 1
    case stopRecording = 2

    var displayString: String {
        switch self {
        case .toggleRecording:
            "⌘⇧9"
        case .stopRecording:
            "⌘⇧0"
        }
    }

    fileprivate var keyCode: UInt32 {
        switch self {
        case .toggleRecording:
            UInt32(kVK_ANSI_9)
        case .stopRecording:
            UInt32(kVK_ANSI_0)
        }
    }
}

final class GlobalHotKeyManager {
    var onAction: ((GlobalHotKeyAction) -> Void)?

    private var hotKeyRefs: [GlobalHotKeyAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    func register() {
        if eventHandler == nil {
            installHandler()
        }

        guard hotKeyRefs.isEmpty else {
            return
        }

        for action in GlobalHotKeyAction.allCases {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x46524331), id: action.rawValue)

            RegisterEventHotKey(
                action.keyCode,
                UInt32(cmdKey | shiftKey),
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

    deinit {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()

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
                      let action = GlobalHotKeyAction(rawValue: hotKeyID.id) else {
                    return noErr
                }

                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
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
