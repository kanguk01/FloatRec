import AppKit
import Foundation
import OSLog

@MainActor
final class CursorTrackingService {
    private let logger = Logger(subsystem: "dev.floatrec.app", category: "cursor-tracking")
    private let cameraHotKeyManager = RecordingCameraHotKeyManager()
    private let cameraHUDController = RecordingCameraHUDController()
    private var trackingTask: Task<Void, Never>?
    private var globalMouseMonitor: Any?
    private var startedAt: TimeInterval?
    private var trackingRect: CGRect?
    private var samples: [CursorTrackSample] = []
    private var clickSamples: [CursorClickSample] = []
    private var cameraControlEvents: [CameraControlEvent] = []
    private var cameraControlStyle: CameraControlStyle = .automatic
    private var previewCameraMode: PreviewCameraMode = .overview

    func startTracking(for source: ResolvedCaptureSource, enabled: Bool, cameraControlStyle: CameraControlStyle) {
        _ = stopTracking()
        self.cameraControlStyle = cameraControlStyle

        guard enabled, let trackingRect = source.autoZoomTrackingRect, trackingRect.width > 0, trackingRect.height > 0 else {
            logger.info(
                "cursor tracking skipped: enabled=\(enabled, privacy: .public) trackingRectAvailable=\(source.autoZoomTrackingRect != nil, privacy: .public)"
            )
            return
        }

        self.trackingRect = trackingRect
        self.startedAt = ProcessInfo.processInfo.systemUptime
        logger.info("cursor tracking started: rect=\(self.rectDescription(trackingRect), privacy: .public)")
        captureSample()
        installGlobalMouseMonitor()
        installCameraHotKeysIfNeeded()

        trackingTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.captureSample()
                }

                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    func stopTracking() -> CursorTrack? {
        captureSample()
        trackingTask?.cancel()
        trackingTask = nil
        removeGlobalMouseMonitor()
        removeCameraHotKeys()
        cameraHUDController.hide()

        defer {
            startedAt = nil
            trackingRect = nil
            samples.removeAll()
            clickSamples.removeAll()
            cameraControlEvents.removeAll()
            cameraControlStyle = .automatic
            previewCameraMode = .overview
        }

        let result = CursorTrack(
            samples: samples,
            clickSamples: clickSamples,
            cameraControlEvents: cameraControlEvents
        )
        logger.info(
            "cursor tracking stopped: samples=\(result.samples.count, privacy: .public) clicks=\(result.clickSamples.count, privacy: .public) cameraEvents=\(result.cameraControlEvents.count, privacy: .public) usable=\(result.isUsableForAutoZoom, privacy: .public)"
        )
        return result.isUsableForAutoZoom || result.hasClicks || result.hasManualCameraEvents ? result : nil
    }

    private func captureSample() {
        guard let startedAt, let trackingRect else {
            return
        }

        let globalLocation = NSEvent.mouseLocation
        guard trackingRect.contains(globalLocation) else {
            return
        }

        let normalizedLocation = CGPoint(
            x: (globalLocation.x - trackingRect.minX) / trackingRect.width,
            y: (globalLocation.y - trackingRect.minY) / trackingRect.height
        )

        let timestamp = ProcessInfo.processInfo.systemUptime - startedAt

        if let lastSample = samples.last {
            let dx = normalizedLocation.x - lastSample.normalizedLocation.x
            let dy = normalizedLocation.y - lastSample.normalizedLocation.y
            let distance = sqrt(dx * dx + dy * dy)

            if distance < 0.0012, timestamp - lastSample.time < 0.05 {
                return
            }
        }

        samples.append(
            CursorTrackSample(
                time: timestamp,
                normalizedLocation: normalizedLocation
            )
        )
    }

    private func installGlobalMouseMonitor() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.captureClick(from: event)
            }
        }
    }

    private func installCameraHotKeysIfNeeded() {
        guard cameraControlStyle == .manualHotkeys else {
            return
        }

        cameraHotKeyManager.onAction = { [weak self] action in
            Task { @MainActor [weak self] in
                self?.captureCameraControl(action)
            }
        }
        cameraHotKeyManager.register()
        cameraHUDController.showHint()
    }

    private func removeCameraHotKeys() {
        cameraHotKeyManager.onAction = nil
        cameraHotKeyManager.unregister()
    }

    private func removeGlobalMouseMonitor() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func captureClick(from event: NSEvent) {
        guard let startedAt, let trackingRect else {
            return
        }

        let globalLocation = event.locationInWindow
        guard trackingRect.contains(globalLocation) else {
            return
        }

        let normalizedLocation = CGPoint(
            x: (globalLocation.x - trackingRect.minX) / trackingRect.width,
            y: (globalLocation.y - trackingRect.minY) / trackingRect.height
        )

        let timestamp = ProcessInfo.processInfo.systemUptime - startedAt
        clickSamples.append(
            CursorClickSample(
                time: timestamp,
                normalizedLocation: normalizedLocation
            )
        )
    }

    private func captureCameraControl(_ action: RecordingCameraHotKeyAction) {
        guard let startedAt else {
            return
        }

        let timestamp = ProcessInfo.processInfo.systemUptime - startedAt
        let actionEvent = CameraControlEvent(
            time: timestamp,
            action: cameraAction(for: action),
            normalizedLocation: currentNormalizedLocation()
        )
        cameraControlEvents.append(actionEvent)
        previewCameraMode = nextPreviewMode(for: action)
        showCameraFeedback(for: action, mode: previewCameraMode)
        logger.info(
            "captured camera control: action=\(actionEvent.action.rawValue, privacy: .public) time=\(timestamp, privacy: .public)"
        )
    }

    private func currentNormalizedLocation() -> CGPoint? {
        if let trackingRect, trackingRect.contains(NSEvent.mouseLocation) {
            let location = NSEvent.mouseLocation
            return CGPoint(
                x: (location.x - trackingRect.minX) / trackingRect.width,
                y: (location.y - trackingRect.minY) / trackingRect.height
            )
        }

        return samples.last?.normalizedLocation
    }

    private func cameraAction(for action: RecordingCameraHotKeyAction) -> CameraControlAction {
        switch action {
        case .toggleSpotlight:
            .toggleSpotlight
        case .toggleFollow:
            .toggleFollow
        case .resetOverview:
            .resetOverview
        }
    }

    private func rectDescription(_ rect: CGRect) -> String {
        "(\(Int(rect.minX)),\(Int(rect.minY))) \(Int(rect.width))x\(Int(rect.height))"
    }

    private func nextPreviewMode(for action: RecordingCameraHotKeyAction) -> PreviewCameraMode {
        switch action {
        case .toggleSpotlight:
            switch previewCameraMode {
            case .spotlight:
                .overview
            case .overview, .follow:
                .spotlight
            }
        case .toggleFollow:
            switch previewCameraMode {
            case .follow:
                .overview
            case .overview, .spotlight:
                .follow
            }
        case .resetOverview:
            .overview
        }
    }

    private func showCameraFeedback(for action: RecordingCameraHotKeyAction, mode: PreviewCameraMode) {
        let title: String
        let detail: String

        switch action {
        case .toggleSpotlight:
            if case .spotlight = mode {
                title = "줌 켜짐"
                detail = "현재 커서 위치로 부드럽게 확대합니다 · \(action.displayString)"
            } else {
                title = "줌 꺼짐"
                detail = "전체 화면 보기로 돌아갑니다 · \(action.displayString)"
            }
        case .toggleFollow:
            if case .follow = mode {
                title = "따라가기 켜짐"
                detail = "커서 이동을 계속 따라갑니다 · \(action.displayString)"
            } else {
                title = "따라가기 꺼짐"
                detail = "현재 카메라 추적을 멈춥니다 · \(action.displayString)"
            }
        case .resetOverview:
            title = "전체 화면 복귀"
            detail = "카메라를 기본 시야로 되돌립니다 · \(action.displayString)"
        }

        cameraHUDController.showState(
            title: title,
            detail: detail
        )
    }
}

private enum PreviewCameraMode {
    case overview
    case spotlight
    case follow
}
