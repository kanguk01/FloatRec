import AppKit
import Foundation

@MainActor
final class CursorTrackingService {
    private var trackingTask: Task<Void, Never>?
    private var globalMouseMonitor: Any?
    private var startedAt: TimeInterval?
    private var trackingRect: CGRect?
    private var samples: [CursorTrackSample] = []
    private var clickSamples: [CursorClickSample] = []

    func startTracking(for source: ResolvedCaptureSource, enabled: Bool) {
        _ = stopTracking()

        guard enabled, let trackingRect = source.autoZoomTrackingRect, trackingRect.width > 0, trackingRect.height > 0 else {
            return
        }

        self.trackingRect = trackingRect
        self.startedAt = ProcessInfo.processInfo.systemUptime
        captureSample()
        installGlobalMouseMonitor()

        trackingTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.captureSample()
                }

                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    func stopTracking() -> CursorTrack? {
        captureSample()
        trackingTask?.cancel()
        trackingTask = nil
        removeGlobalMouseMonitor()

        defer {
            startedAt = nil
            trackingRect = nil
            samples.removeAll()
            clickSamples.removeAll()
        }

        let result = CursorTrack(samples: samples, clickSamples: clickSamples)
        return result.isUsableForAutoZoom || result.hasClicks ? result : nil
    }

    private func captureSample() {
        guard let startedAt, let trackingRect else {
            return
        }

        let globalLocation = NSEvent.mouseLocation
        let clampedPoint = CGPoint(
            x: min(max(globalLocation.x, trackingRect.minX), trackingRect.maxX),
            y: min(max(globalLocation.y, trackingRect.minY), trackingRect.maxY)
        )

        let normalizedLocation = CGPoint(
            x: (clampedPoint.x - trackingRect.minX) / trackingRect.width,
            y: (clampedPoint.y - trackingRect.minY) / trackingRect.height
        )

        let timestamp = ProcessInfo.processInfo.systemUptime - startedAt

        if let lastSample = samples.last {
            let dx = normalizedLocation.x - lastSample.normalizedLocation.x
            let dy = normalizedLocation.y - lastSample.normalizedLocation.y
            let distance = sqrt(dx * dx + dy * dy)

            if distance < 0.002, timestamp - lastSample.time < 0.12 {
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
}
