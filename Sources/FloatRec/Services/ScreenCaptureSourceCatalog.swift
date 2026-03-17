import Foundation
import ScreenCaptureKit

enum ResolvedCaptureSource {
    case display(SCDisplay, sourceLabel: String)
    case window(SCWindow, sourceLabel: String)

    var sourceLabel: String {
        switch self {
        case let .display(_, sourceLabel), let .window(_, sourceLabel):
            sourceLabel
        }
    }

    func makeFilter() -> SCContentFilter {
        switch self {
        case let .display(display, _):
            return SCContentFilter(display: display, excludingWindows: [])
        case let .window(window, _):
            return SCContentFilter(desktopIndependentWindow: window)
        }
    }
}

@MainActor
final class ScreenCaptureSourceCatalog {
    private var displaySourcesByID: [String: SCDisplay] = [:]
    private var windowSourcesByID: [String: SCWindow] = [:]

    func loadSnapshot() async throws -> CaptureSourceSnapshot {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        let displays = shareableContent.displays.enumerated().map { index, display in
            let option = CaptureSourceOption(
                id: "display-\(display.displayID)",
                title: "디스플레이 \(index + 1)",
                detail: "\(Int(display.width))×\(Int(display.height))",
                sourceLabel: "디스플레이 \(index + 1)"
            )
            displaySourcesByID[option.id] = display
            return option
        }

        let windows = shareableContent.windows.compactMap { window -> CaptureSourceOption? in
            let windowTitle = (window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            let appName = window.owningApplication?.applicationName ?? "앱 이름 없음"

            guard !windowTitle.isEmpty else {
                return nil
            }

            let size = window.frame.size
            let option = CaptureSourceOption(
                id: "window-\(window.windowID)",
                title: windowTitle,
                detail: "\(appName) · \(Int(size.width))×\(Int(size.height))",
                sourceLabel: "\(appName) · \(windowTitle)"
            )
            windowSourcesByID[option.id] = window
            return option
        }
        .sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        return CaptureSourceSnapshot(displays: displays, windows: windows)
    }

    func resolveSource(mode: CaptureMode, selectedSourceID: String?) async throws -> ResolvedCaptureSource? {
        if displaySourcesByID.isEmpty && windowSourcesByID.isEmpty {
            _ = try await loadSnapshot()
        }

        guard let selectedSourceID else {
            return nil
        }

        switch mode {
        case .display:
            guard let display = displaySourcesByID[selectedSourceID] else {
                return nil
            }

            return .display(display, sourceLabel: "디스플레이 녹화")
        case .window:
            guard let window = windowSourcesByID[selectedSourceID] else {
                return nil
            }

            let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let appName = window.owningApplication?.applicationName ?? "윈도우"
            let sourceLabel = title?.isEmpty == false ? "\(appName) · \(title!)" : appName
            return .window(window, sourceLabel: sourceLabel)
        case .area:
            return nil
        }
    }
}
