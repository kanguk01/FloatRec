import AppKit
import CoreGraphics
import Foundation
import OSLog

struct ScreenRecordingPermissionService {
    private static let logger = Logger(subsystem: "dev.floatrec.app", category: "permission")

    enum RuntimeInstallIssue {
        case diskImage
        case translocated

        var guidanceText: String {
            switch self {
            case .diskImage:
                "현재 FloatRec이 디스크 이미지에서 직접 실행 중입니다. 응용 프로그램 폴더로 옮긴 뒤 다시 실행해야 권한 인식이 안정적입니다."
            case .translocated:
                "현재 FloatRec이 임시 실행 위치에서 열려 있습니다. 응용 프로그램 폴더로 옮긴 뒤 다시 실행해 주세요."
            }
        }
    }

    func canAccess() -> Bool {
        let granted = CGPreflightScreenCaptureAccess()
        Self.logger.info(
            "preflight screen capture access: granted=\(granted, privacy: .public) bundlePath=\(Bundle.main.bundleURL.path, privacy: .public)"
        )
        return granted
    }

    func ensureAccess() async -> Bool {
        if canAccess() {
            Self.logger.info("screen capture access already granted before request")
            return true
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let granted = CGRequestScreenCaptureAccess()
                Self.logger.info("screen capture access request finished: granted=\(granted, privacy: .public)")
                continuation.resume(returning: granted)
            }
        }
    }

    func openSettings() {
        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else {
            return
        }

        NSWorkspace.shared.open(settingsURL)
    }

    func runtimeInstallIssue() -> RuntimeInstallIssue? {
        let bundlePath = Bundle.main.bundleURL.resolvingSymlinksInPath().path

        if bundlePath.hasPrefix("/Volumes/") {
            return .diskImage
        }

        if bundlePath.contains("/AppTranslocation/") {
            return .translocated
        }

        return nil
    }

    func deniedAccessMessage() -> String {
        var lines = ["화면 녹화 권한이 필요합니다. 시스템 설정에서 FloatRec 접근을 허용해 주세요."]

        if let issue = runtimeInstallIssue() {
            lines.append(issue.guidanceText)
        } else {
            lines.append("권한을 방금 켰다면 FloatRec을 완전히 종료한 뒤 다시 실행해 주세요.")
        }

        return lines.joined(separator: "\n")
    }

    func noAccessSourceRefreshMessage() -> String {
        var lines = ["화면 녹화 권한을 허용한 뒤 캡처 소스를 불러올 수 있습니다."]

        if let issue = runtimeInstallIssue() {
            lines.append(issue.guidanceText)
        }

        return lines.joined(separator: "\n")
    }

    func openApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
    }

    func revealRunningApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}
