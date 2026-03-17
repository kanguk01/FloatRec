import Foundation

enum RecordingState {
    case idle
    case requestingPermission
    case recording(startedAt: Date)
    case processing

    var isBusy: Bool {
        switch self {
        case .requestingPermission, .processing:
            true
        case .idle, .recording:
            false
        }
    }

    var isRecording: Bool {
        if case .recording = self {
            return true
        }

        return false
    }

    var statusText: String {
        switch self {
        case .idle:
            "대기 중"
        case .requestingPermission:
            "권한 확인 중"
        case .recording:
            "녹화 중"
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
        case .requestingPermission, .processing:
            "작업 중"
        }
    }

    var primaryActionSymbolName: String {
        switch self {
        case .idle:
            "record.circle"
        case .recording:
            "stop.circle.fill"
        case .requestingPermission, .processing:
            "hourglass"
        }
    }
}
