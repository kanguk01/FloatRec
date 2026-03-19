import Foundation

enum RecordingState {
    case idle
    case requestingPermission
    case recording(startedAt: Date)
    case paused(startedAt: Date, pausedAt: Date)
    case processing

    var isBusy: Bool {
        switch self {
        case .requestingPermission, .processing:
            true
        case .idle, .recording, .paused:
            false
        }
    }

    var isRecording: Bool {
        if case .recording = self {
            return true
        }

        return false
    }

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .idle:
            "대기 중"
        case .requestingPermission:
            "준비 중"
        case .recording:
            "녹화 중"
        case .paused:
            "일시정지"
        case .processing:
            "클립 정리 중"
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .idle:
            "녹화 시작"
        case .recording:
            "녹화 종료"
        case .paused:
            "녹화 재개"
        case .requestingPermission, .processing:
            "준비 중"
        }
    }

    var primaryActionSymbolName: String {
        switch self {
        case .idle:
            "record.circle"
        case .recording:
            "stop.circle.fill"
        case .paused:
            "play.circle"
        case .requestingPermission, .processing:
            "hourglass"
        }
    }
}
