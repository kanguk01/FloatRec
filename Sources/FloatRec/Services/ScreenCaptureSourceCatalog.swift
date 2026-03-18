import AppKit
import Foundation
import OSLog
import ScreenCaptureKit

private enum SourceCatalogError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut:
            "캡처 소스 목록을 불러오는 시간이 너무 오래 걸렸습니다. 다시 시도해 주세요."
        }
    }
}

private final class ShareableContentBox: @unchecked Sendable {
    let content: SCShareableContent

    init(_ content: SCShareableContent) {
        self.content = content
    }
}

enum ResolvedCaptureSource {
    case display(SCDisplay, sourceLabel: String)
    case window(SCWindow, sourceLabel: String)
    case area(SCDisplay, sourceRect: CGRect, sourceLabel: String)

    var sourceLabel: String {
        switch self {
        case let .display(_, sourceLabel),
             let .window(_, sourceLabel),
             let .area(_, _, sourceLabel):
            sourceLabel
        }
    }

    func makeFilter() -> SCContentFilter {
        switch self {
        case let .display(display, _):
            return SCContentFilter(display: display, excludingWindows: [])
        case let .window(window, _):
            return SCContentFilter(desktopIndependentWindow: window)
        case let .area(display, _, _):
            return SCContentFilter(display: display, excludingWindows: [])
        }
    }

    var sourceRect: CGRect? {
        switch self {
        case .display, .window:
            nil
        case let .area(_, sourceRect, _):
            sourceRect
        }
    }

    var autoZoomTrackingRect: CGRect? {
        let screenCaptureRect: CGRect

        switch self {
        case let .display(display, _):
            screenCaptureRect = display.frame
        case let .window(window, _):
            screenCaptureRect = window.frame
        case let .area(display, sourceRect, _):
            screenCaptureRect = CGRect(
                x: display.frame.minX + sourceRect.minX,
                y: display.frame.minY + sourceRect.minY,
                width: sourceRect.width,
                height: sourceRect.height
            )
        }

        return Self.appKitGlobalRect(from: screenCaptureRect)
    }

    private static func appKitGlobalRect(from screenCaptureRect: CGRect) -> CGRect {
        let referenceTop = NSScreen.screens
            .first(where: { $0.frame.origin == .zero })?
            .frame
            .maxY ?? NSScreen.main?.frame.maxY ?? screenCaptureRect.maxY

        return CGRect(
            x: screenCaptureRect.minX,
            y: referenceTop - screenCaptureRect.maxY,
            width: screenCaptureRect.width,
            height: screenCaptureRect.height
        )
    }
}

@MainActor
final class ScreenCaptureSourceCatalog {
    private let logger = Logger(subsystem: "dev.floatrec.app", category: "source-catalog")
    private var displaySourcesByID: [String: SCDisplay] = [:]
    private var windowSourcesByID: [String: SCWindow] = [:]
    private let snapshotTimeout: Duration = .seconds(5)

    func loadSnapshot() async throws -> CaptureSourceSnapshot {
        logger.info("loading shareable content snapshot")
        let shareableContent: SCShareableContent
        do {
            shareableContent = try await loadShareableContentWithTimeout()
        } catch {
            logger.error("failed loading shareable content: \(error.localizedDescription, privacy: .public)")
            throw error
        }

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
            let size = window.frame.size
            let title = windowTitle.isEmpty ? "\(appName) 창" : windowTitle
            let sourceLabel = windowTitle.isEmpty ? appName : "\(appName) · \(windowTitle)"
            let option = CaptureSourceOption(
                id: "window-\(window.windowID)",
                title: title,
                detail: "\(appName) · \(Int(size.width))×\(Int(size.height))",
                sourceLabel: sourceLabel
            )
            windowSourcesByID[option.id] = window
            return option
        }
        .sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        logger.info(
            "loaded shareable content snapshot: displays=\(displays.count, privacy: .public) windows=\(windows.count, privacy: .public)"
        )

        return CaptureSourceSnapshot(displays: displays, windows: windows)
    }

    private func loadShareableContentWithTimeout() async throws -> SCShareableContent {
        try await withThrowingTaskGroup(of: ShareableContentBox.self) { group in
            group.addTask {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )
                return ShareableContentBox(content)
            }
            group.addTask { [snapshotTimeout] in
                try await Task.sleep(for: snapshotTimeout)
                throw SourceCatalogError.timedOut
            }

            let result = try await group.next() ?? {
                throw SourceCatalogError.timedOut
            }()
            group.cancelAll()
            return result.content
        }
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

    func resolveAreaSelection(_ areaSelection: AreaSelection) async throws -> ResolvedCaptureSource? {
        if displaySourcesByID.isEmpty {
            _ = try await loadSnapshot()
        }

        let displayID = areaSelection.displayID
        guard let display = displaySourcesByID["display-\(displayID)"] else {
            return nil
        }

        return .area(
            display,
            sourceRect: areaSelection.normalizedRect,
            sourceLabel: areaSelection.sourceLabel
        )
    }
}
