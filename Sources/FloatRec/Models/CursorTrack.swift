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

    var isUsableForAutoZoom: Bool {
        samples.count >= 2
    }

    var hasClicks: Bool {
        !clickSamples.isEmpty
    }
}
