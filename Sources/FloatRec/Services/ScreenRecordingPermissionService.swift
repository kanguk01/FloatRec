import AppKit
import CoreGraphics
import Foundation

struct ScreenRecordingPermissionService {
    func canAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func ensureAccess() async -> Bool {
        if canAccess() {
            return true
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let granted = CGRequestScreenCaptureAccess()
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
}
