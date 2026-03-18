import Foundation

enum CameraControlStyle: String, CaseIterable, Identifiable {
    case manualHotkeys

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manualHotkeys:
            "수동 키"
        }
    }

    var summary: String {
        switch self {
        case .manualHotkeys:
            "녹화 중 단축키로 줌과 팔로우를 직접 토글합니다."
        }
    }
}

enum CameraControlAction: String, Sendable {
    case stepZoom
    case toggleFollow
    case resetOverview
    case toggleSpotlightEffect
}

struct CameraControlEvent: Sendable {
    let time: TimeInterval
    let action: CameraControlAction
    let normalizedLocation: CGPoint?
}
