import Foundation
import ScreenCaptureKit

actor ScreenCaptureSourceCatalog {
    func loadSnapshot() async throws -> CaptureSourceSnapshot {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        let displays = shareableContent.displays.enumerated().map { index, display in
            CaptureSourceOption(
                id: "display-\(display.displayID)",
                title: "디스플레이 \(index + 1)",
                detail: "\(Int(display.width))×\(Int(display.height))",
                sourceLabel: "디스플레이 \(index + 1)"
            )
        }

        let windows = shareableContent.windows.compactMap { window -> CaptureSourceOption? in
            let windowTitle = (window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            let appName = window.owningApplication?.applicationName ?? "앱 이름 없음"

            guard !windowTitle.isEmpty else {
                return nil
            }

            let size = window.frame.size
            return CaptureSourceOption(
                id: "window-\(window.windowID)",
                title: windowTitle,
                detail: "\(appName) · \(Int(size.width))×\(Int(size.height))",
                sourceLabel: "\(appName) · \(windowTitle)"
            )
        }
        .sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        return CaptureSourceSnapshot(displays: displays, windows: windows)
    }
}
