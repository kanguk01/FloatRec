import AppKit
import Foundation
import OSLog

@MainActor
final class CursorTrackingService {
    private static let maxManualZoomStep = 4

    private let logger = Logger(subsystem: "dev.floatrec.app", category: "cursor-tracking")
    private let cameraHotKeyManager = RecordingCameraHotKeyManager()
    private var statusHUD: RecordingStatusHUDController { RecordingStatusHUDController.shared }
    private let previewOverlay = CameraPreviewOverlayController()
    private var isLivePreviewEnabled = false
    private var trackingTask: Task<Void, Never>?
    private var globalMouseMonitor: Any?
    private var startedAt: TimeInterval?
    private var trackingRect: CGRect?
    private var samples: [CursorTrackSample] = []
    private var clickSamples: [CursorClickSample] = []
    private var cameraControlEvents: [CameraControlEvent] = []
    private var cameraControlStyle: CameraControlStyle = .manualHotkeys
    private var previewCameraState = PreviewCameraState.overview
    private var zoomAnchorInView: CGPoint?

    func startTracking(
        for source: ResolvedCaptureSource,
        enabled: Bool,
        cameraControlStyle: CameraControlStyle,
        defaultManualSpotlightEnabled: Bool,
        isLivePreviewEnabled: Bool = false
    ) {
        _ = stopTracking()
        self.cameraControlStyle = cameraControlStyle
        self.isLivePreviewEnabled = isLivePreviewEnabled
        self.previewCameraState = PreviewCameraState(
            mode: .overview,
            zoomStep: 0,
            isSpotlightEnabled: defaultManualSpotlightEnabled
        )

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

        if isLivePreviewEnabled {
            previewOverlay.show(trackingRect: trackingRect)
        }

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
        statusHUD.clearCameraStatus()
        previewOverlay.hide()

        defer {
            startedAt = nil
            trackingRect = nil
            samples.removeAll()
            clickSamples.removeAll()
            cameraControlEvents.removeAll()
            cameraControlStyle = .manualHotkeys
            previewCameraState = .overview
            zoomAnchorInView = nil
            isLivePreviewEnabled = false
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
        refreshCameraHUD()
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
        let previousZoomStep = previewCameraState.zoomStep
        previewCameraState = nextPreviewState(for: action)

        if previousZoomStep == 0 && previewCameraState.zoomStep > 0 {
            zoomAnchorInView = cursorLocationInTrackingView()
        }
        if previewCameraState.mode == .overview {
            zoomAnchorInView = nil
        }
        if action == .toggleFollow {
            zoomAnchorInView = cursorLocationInTrackingView()
        }

        refreshCameraHUD()
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
        case .stepZoom:
            .stepZoom
        case .toggleFollow:
            .toggleFollow
        case .resetOverview:
            .resetOverview
        case .toggleSpotlightEffect:
            .toggleSpotlightEffect
        }
    }

    private func rectDescription(_ rect: CGRect) -> String {
        "(\(Int(rect.minX)),\(Int(rect.minY))) \(Int(rect.width))x\(Int(rect.height))"
    }

    private func nextPreviewState(for action: RecordingCameraHotKeyAction) -> PreviewCameraState {
        switch action {
        case .stepZoom:
            let nextZoomStep: Int
            switch previewCameraState.mode {
            case .spotlight, .follow:
                nextZoomStep = min(previewCameraState.zoomStep + 1, Self.maxManualZoomStep)
            case .overview:
                nextZoomStep = max(previewCameraState.zoomStep, 1)
            }
            return PreviewCameraState(
                mode: .spotlight,
                zoomStep: nextZoomStep,
                isSpotlightEnabled: previewCameraState.isSpotlightEnabled
            )
        case .toggleFollow:
            switch previewCameraState.mode {
            case .follow:
                return .overview
            case .overview, .spotlight:
                return PreviewCameraState(
                    mode: .follow,
                    zoomStep: max(previewCameraState.zoomStep, 1),
                    isSpotlightEnabled: previewCameraState.isSpotlightEnabled
                )
            }
        case .resetOverview:
            return .overview
        case .toggleSpotlightEffect:
            return PreviewCameraState(
                mode: previewCameraState.mode,
                zoomStep: previewCameraState.zoomStep,
                isSpotlightEnabled: !previewCameraState.isSpotlightEnabled
            )
        }
    }

    private func cursorLocationInTrackingView() -> CGPoint? {
        guard let trackingRect else { return nil }
        let global = NSEvent.mouseLocation
        return CGPoint(
            x: global.x - trackingRect.origin.x,
            y: global.y - trackingRect.origin.y
        )
    }

    private func refreshCameraHUD() {
        let title = hudTitle(for: previewCameraState)
        let detail = hudDetail(for: previewCameraState)
        statusHUD.updateCameraStatus("\(title) · \(detail)")

        if isLivePreviewEnabled {
            previewOverlay.update(
                state: CameraPreviewState(
                    zoomStep: previewCameraState.zoomStep,
                    isFollowing: previewCameraState.mode == .follow,
                    isSpotlightEnabled: previewCameraState.isSpotlightEnabled,
                    anchorPoint: zoomAnchorInView
                ),
                cursorLocation: NSEvent.mouseLocation
            )
        }
    }

    private func hudTitle(for state: PreviewCameraState) -> String {
        let spotlightLabel = state.isSpotlightEnabled ? "스포트 ON" : "스포트 OFF"

        switch state.mode {
        case .overview:
            return "전체 화면 · \(spotlightLabel)"
        case .spotlight:
            return "줌 \(state.zoomStep)단계 · \(spotlightLabel)"
        case .follow:
            return "따라가기 \(state.zoomStep)단계 · \(spotlightLabel)"
        }
    }

    private func hudDetail(for state: PreviewCameraState) -> String {
        return "⌃1 확대 · ⌃2 따라가기 · ⌃3 전체 · ⌃4 스포트"
    }
}

private struct PreviewCameraState {
    let mode: PreviewCameraMode
    let zoomStep: Int
    let isSpotlightEnabled: Bool

    static let overview = PreviewCameraState(mode: .overview, zoomStep: 0, isSpotlightEnabled: true)
}

private enum PreviewCameraMode {
    case overview
    case spotlight
    case follow
}
