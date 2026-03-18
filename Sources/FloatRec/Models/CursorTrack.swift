import CoreGraphics
import Foundation

struct CursorTrackSample: Sendable {
    let time: TimeInterval
    let normalizedLocation: CGPoint
}

struct CursorClickSample: Sendable {
    let time: TimeInterval
    let normalizedLocation: CGPoint
}

struct CursorTrack: Sendable {
    let samples: [CursorTrackSample]
    let clickSamples: [CursorClickSample]
    let cameraControlEvents: [CameraControlEvent]

    init(
        samples: [CursorTrackSample],
        clickSamples: [CursorClickSample],
        cameraControlEvents: [CameraControlEvent] = []
    ) {
        self.samples = samples
        self.clickSamples = clickSamples
        self.cameraControlEvents = cameraControlEvents
    }

    var isUsableForAutoZoom: Bool {
        samples.count >= 2
    }

    var hasClicks: Bool {
        !clickSamples.isEmpty
    }

    var hasManualCameraEvents: Bool {
        !cameraControlEvents.isEmpty
    }
}
