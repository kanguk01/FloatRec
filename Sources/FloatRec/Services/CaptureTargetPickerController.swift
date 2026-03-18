import Foundation
import AppKit
@preconcurrency import ScreenCaptureKit

@MainActor
final class CaptureTargetPickerController: NSObject {
    struct Selection: Sendable {
        let mode: CaptureMode
        let source: CaptureSourceOption
    }

    var onSelection: ((Selection) -> Void)?
    var onCancel: (() -> Void)?
    var onError: ((Error) -> Void)?

    private let picker = SCContentSharingPicker.shared
    private var isObserving = false

    override init() {
        super.init()
        picker.isActive = false
        picker.maximumStreamCount = 1
    }

    func present(for mode: CaptureMode) {
        guard mode != .area else {
            return
        }

        attachObserverIfNeeded()
        NSApp.activate(ignoringOtherApps: true)

        var configuration = picker.defaultConfiguration
        configuration.allowedPickerModes = allowedModes(for: mode)
        configuration.allowsChangingSelectedContent = false
        picker.defaultConfiguration = configuration
        picker.isActive = false
        picker.isActive = true
        picker.present(using: contentStyle(for: mode))
    }

    func cancelPresentation() {
        deactivatePicker()
    }

    private func allowedModes(for mode: CaptureMode) -> SCContentSharingPickerMode {
        switch mode {
        case .display:
            [.singleDisplay]
        case .window:
            [.singleWindow]
        case .area:
            []
        }
    }

    private func contentStyle(for mode: CaptureMode) -> SCShareableContentStyle {
        switch mode {
        case .display:
            .display
        case .window:
            .window
        case .area:
            .none
        }
    }

    @available(macOS 15.2, *)
    nonisolated private static func selection(from filter: SCContentFilter) -> Selection? {
        switch filter.style {
        case .display:
            guard let display = filter.includedDisplays.first else {
                return nil
            }
            return Selection(
                mode: .display,
                source: CaptureSourceOption(
                    id: "display-\(display.displayID)",
                    title: "디스플레이",
                    detail: "\(Int(display.width))×\(Int(display.height))",
                    sourceLabel: "디스플레이 녹화"
                )
            )
        case .window:
            guard let window = filter.includedWindows.first else {
                return nil
            }
            let windowTitle = (window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            let appName = window.owningApplication?.applicationName ?? "앱 이름 없음"
            let title = windowTitle.isEmpty ? "\(appName) 창" : windowTitle
            let sourceLabel = windowTitle.isEmpty ? appName : "\(appName) · \(windowTitle)"
            return Selection(
                mode: .window,
                source: CaptureSourceOption(
                    id: "window-\(window.windowID)",
                    title: title,
                    detail: "\(appName) · \(Int(window.frame.width))×\(Int(window.frame.height))",
                    sourceLabel: sourceLabel
                )
            )
        default:
            return nil
        }
    }

    private func attachObserverIfNeeded() {
        guard !isObserving else {
            return
        }

        picker.add(self)
        isObserving = true
    }

    private func detachObserverIfNeeded() {
        guard isObserving else {
            return
        }

        picker.remove(self)
        isObserving = false
    }

    private func deactivatePicker() {
        picker.isActive = false
        detachObserverIfNeeded()
    }
}

@MainActor
extension CaptureTargetPickerController: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        Task { @MainActor [weak self] in
            self?.deactivatePicker()
            self?.onCancel?()
        }
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        let selection: Selection?
        if #available(macOS 15.2, *) {
            selection = Self.selection(from: filter)
        } else {
            selection = nil
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            guard let selection else {
                self.deactivatePicker()
                self.onError?(PickerError.unsupportedSelection)
                return
            }

            self.deactivatePicker()
            self.onSelection?(selection)
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in
            self?.deactivatePicker()
            self?.onError?(error)
        }
    }
}

private enum PickerError: LocalizedError {
    case unsupportedSelection

    var errorDescription: String? {
        switch self {
        case .unsupportedSelection:
            "선택 결과를 확인하지 못했습니다. macOS 15.2 이상에서 다시 시도해 주세요."
        }
    }
}
