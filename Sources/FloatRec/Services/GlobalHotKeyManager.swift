import AppKit
import Carbon
import Foundation
import OSLog

private let hotKeyLogger = Logger(subsystem: "dev.floatrec.app", category: "hotkey")

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

    fileprivate var carbonKeyCode: UInt32 {
        switch self {
        case .toggleRecording:
            UInt32(kVK_ANSI_9)
        case .stopRecording:
            UInt32(kVK_ANSI_0)
        }
    }

    fileprivate var nsKeyCode: UInt16 {
        UInt16(carbonKeyCode)
    }
}

final class GlobalHotKeyManager {
    private static let hotKeySignature = OSType(0x46524331)

    var onAction: ((GlobalHotKeyAction) -> Void)?

    private var hotKeyRefs: [GlobalHotKeyAction: EventHotKeyRef] = [:]
    private var carbonEventHandler: EventHandlerRef?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func register() {
        registerCarbonHotKeys()
        installCarbonHandler()
        installNSEventMonitors()
    }

    deinit {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let carbonEventHandler {
            RemoveEventHandler(carbonEventHandler)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    private func registerCarbonHotKeys() {
        guard hotKeyRefs.isEmpty else { return }

        for action in GlobalHotKeyAction.allCases {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: action.rawValue)

            let status = RegisterEventHotKey(
                action.carbonKeyCode,
                UInt32(cmdKey | shiftKey),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )

            if status == noErr, let hotKeyRef {
                hotKeyRefs[action] = hotKeyRef
                hotKeyLogger.info("carbon hotkey registered: \(action.displayString, privacy: .public)")
            } else {
                hotKeyLogger.error("carbon hotkey registration failed: \(action.displayString, privacy: .public) status=\(status)")
            }
        }
    }

    private func installCarbonHandler() {
        guard carbonEventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return noErr }

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
                      hotKeyID.signature == GlobalHotKeyManager.hotKeySignature,
                      let action = GlobalHotKeyAction(rawValue: hotKeyID.id) else {
                    return OSStatus(eventNotHandledErr)
                }

                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                hotKeyLogger.info("carbon event received: \(action.displayString, privacy: .public)")
                manager.onAction?(action)
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &carbonEventHandler
        )
    }

    private func installNSEventMonitors() {
        guard globalMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .systemDefined]) { [weak self] event in
            self?.handleNSEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .systemDefined]) { [weak self] event in
            if self?.handleNSEvent(event) == true {
                return nil
            }
            return event
        }

        hotKeyLogger.info("NSEvent monitors installed")
    }

    @discardableResult
    private func handleNSEvent(_ event: NSEvent) -> Bool {
        if event.type == .systemDefined, event.subtype.rawValue == 6 {
            return handleSystemDefinedHotKey(event)
        }

        if event.type == .keyDown {
            return handleKeyDown(event)
        }

        return false
    }

    private func handleSystemDefinedHotKey(_ event: NSEvent) -> Bool {
        let data = event.data1
        let keyCode = UInt32((data & 0xFFFF0000) >> 16)
        let keyDown = (data & 0x0100) == 0

        guard keyDown else { return false }

        for action in GlobalHotKeyAction.allCases {
            if action.carbonKeyCode == keyCode {
                hotKeyLogger.info("system-defined hotkey: \(action.displayString, privacy: .public)")
                onAction?(action)
                return true
            }
        }
        return false
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == [.command, .shift] else { return false }

        guard let action = GlobalHotKeyAction.allCases.first(where: { $0.nsKeyCode == event.keyCode }) else {
            return false
        }

        hotKeyLogger.info("keyDown hotkey: \(action.displayString, privacy: .public)")
        onAction?(action)
        return true
    }
}
