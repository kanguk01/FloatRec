import CoreGraphics
import Foundation

struct AreaSelection {
    let displayID: CGDirectDisplayID
    let rect: CGRect

    var normalizedRect: CGRect {
        rect.standardized.integral
    }

    var sourceLabel: String {
        let width = Int(normalizedRect.width.rounded())
        let height = Int(normalizedRect.height.rounded())
        return "영역 \(width)×\(height)"
    }
}

enum AreaSelectionError: LocalizedError {
    case cancelled
    case unavailableScreen
    case invalidSelection

    var errorDescription: String? {
        switch self {
        case .cancelled:
            nil
        case .unavailableScreen:
            "영역 선택에 사용할 화면을 찾지 못했습니다."
        case .invalidSelection:
            "너무 작은 영역은 녹화할 수 없습니다."
        }
    }
}
