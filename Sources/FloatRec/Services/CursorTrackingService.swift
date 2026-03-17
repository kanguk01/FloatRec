import AppKit
import Foundation

@MainActor
final class CursorTrackingService {
    private var trackingTask: Task<Void, Never>?
    private var startedAt: TimeInterval?
    private var trackingRect: CGRect?
    private var samples: [CursorTrackSample] = []

    func startTracking(for source: ResolvedCaptureSource, enabled: Bool) {
        _ = stopTracking()

        guard enabled, let trackingRect = source.autoZoomTrackingRect, trackingRect.width > 0, trackingRect.height > 0 else {
            return
        }

        self.trackingRect = trackingRect
        self.startedAt = ProcessInfo.processInfo.systemUptime
        captureSample()

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

        defer {
            startedAt = nil
            trackingRect = nil
            samples.removeAll()
        }

        let result = CursorTrack(samples: samples)
        return result.isUsableForAutoZoom ? result : nil
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
}
