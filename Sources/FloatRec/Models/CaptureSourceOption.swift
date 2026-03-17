import Foundation

enum CaptureMode: String, CaseIterable, Identifiable {
    case display
    case window
    case area

    var id: String { rawValue }

    var title: String {
        switch self {
        case .display:
            "디스플레이"
        case .window:
            "윈도우"
        case .area:
            "영역"
        }
    }

    var helperText: String {
        switch self {
        case .display:
            "화면 전체를 캡처합니다."
        case .window:
            "특정 앱 창만 캡처합니다."
        case .area:
            "cmd+shift+5와 비슷한 영역 선택 UI를 다음 단계에서 붙입니다."
        }
    }
}

struct CaptureSourceOption: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let sourceLabel: String
}

struct CaptureSourceSnapshot {
    let displays: [CaptureSourceOption]
    let windows: [CaptureSourceOption]
}
