import Foundation
import AppKit
@preconcurrency import ScreenCaptureKit

@MainActor
final class CaptureTargetPickerController: NSObject {
    struct Selection: @unchecked Sendable {
        let mode: CaptureMode
        let source: CaptureSourceOption
        let resolvedSource: ResolvedCaptureSource
    }

    var onSelection: ((Selection) -> Void)?
    var onCancel: (() -> Void)?
    var onError: ((Error) -> Void)?

    private let picker = SCContentSharingPicker.shared
    private var isObserving = false
    private var selectionContinuation: CheckedContinuation<Selection, Error>?

    override init() {
        super.init()
        picker.isActive = false
        picker.maximumStreamCount = 1
    }

    func present(for mode: CaptureMode) {
        guard mode != .area else {
            return
        }

        guard selectionContinuation == nil else {
            return
        }

        presentPicker(for: mode)
    }

    func selectTarget(for mode: CaptureMode) async throws -> Selection {
        guard mode != .area else {
            throw PickerError.unsupportedSelection
        }

        guard selectionContinuation == nil else {
            throw PickerError.selectionAlreadyInProgress
        }

        return try await withCheckedThrowingContinuation { continuation in
            selectionContinuation = continuation
            presentPicker(for: mode)
        }
    }

    private func presentPicker(for mode: CaptureMode) {
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
        if selectionContinuation != nil {
            finishWithCancel()
            return
        }

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
                ),
                resolvedSource: .display(display, sourceLabel: "디스플레이 녹화")
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
                ),
                resolvedSource: .window(window, sourceLabel: sourceLabel)
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

    private func finishSelection(_ selection: Selection) {
        deactivatePicker()
        onSelection?(selection)
        selectionContinuation?.resume(returning: selection)
        selectionContinuation = nil
    }

    private func finishWithCancel() {
        deactivatePicker()
        onCancel?()
        selectionContinuation?.resume(throwing: PickerError.cancelled)
        selectionContinuation = nil
    }

    private func finishWithError(_ error: Error) {
        deactivatePicker()
        onError?(error)
        selectionContinuation?.resume(throwing: error)
        selectionContinuation = nil
    }
}

@MainActor
extension CaptureTargetPickerController: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        Task { @MainActor [weak self] in
            self?.finishWithCancel()
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
                self.finishWithError(PickerError.unsupportedSelection)
                return
            }

            self.finishSelection(selection)
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in
            self?.finishWithError(error)
        }
    }
}

enum PickerError: LocalizedError {
    case unsupportedSelection
    case cancelled
    case selectionAlreadyInProgress

    var errorDescription: String? {
        switch self {
        case .unsupportedSelection:
            "선택 결과를 확인하지 못했습니다. macOS 15.2 이상에서 다시 시도해 주세요."
        case .cancelled:
            "캡처 대상 선택이 취소되었습니다."
        case .selectionAlreadyInProgress:
            "이미 캡처 대상 선택이 진행 중입니다."
        }
    }
}
