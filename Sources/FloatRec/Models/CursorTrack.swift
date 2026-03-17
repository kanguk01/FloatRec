import CoreGraphics
import Foundation

struct CursorTrackSample: Sendable {
    let time: TimeInterval
    let normalizedLocation: CGPoint
}

struct CursorTrack: Sendable {
    let samples: [CursorTrackSample]

    var isUsableForAutoZoom: Bool {
        samples.count >= 2
    }
}
