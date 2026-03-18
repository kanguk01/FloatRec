import Foundation

enum CameraControlStyle: String, CaseIterable, Identifiable {
    case automatic
    case manualHotkeys

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            "자동"
        case .manualHotkeys:
            "수동 키"
        }
    }

    var summary: String {
        switch self {
        case .automatic:
            "커서 움직임을 보고 자동으로 확대와 이동을 계산합니다."
        case .manualHotkeys:
            "녹화 중 단축키로 줌과 팔로우를 직접 토글합니다."
        }
    }
}

enum CameraControlAction: String, Sendable {
    case toggleSpotlight
    case toggleFollow
    case resetOverview
}

struct CameraControlEvent: Sendable {
    let time: TimeInterval
    let action: CameraControlAction
    let normalizedLocation: CGPoint?
}
