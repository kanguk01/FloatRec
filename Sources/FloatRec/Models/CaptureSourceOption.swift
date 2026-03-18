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
            "녹화 시작을 누르면 디스플레이를 고르고 바로 녹화합니다."
        case .window:
            "녹화 시작을 누르면 윈도우를 고르고 바로 녹화합니다."
        case .area:
            "녹화 시작을 누르면 cmd+shift+5처럼 드래그로 영역을 선택합니다."
        }
    }
}

struct CaptureSourceOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let sourceLabel: String
}

struct CaptureSourceSnapshot: Sendable {
    let displays: [CaptureSourceOption]
    let windows: [CaptureSourceOption]
}
