import AppKit
import OSLog
import Sparkle

private let logger = Logger(subsystem: "dev.floatrec.app", category: "sparkle")

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appModel: AppModel?
    private var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        logger.info("Sparkle 초기화 시작")

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        logger.info("Sparkle 초기화 완료, canCheckForUpdates: \(self.updaterController?.updater.canCheckForUpdates ?? false)")

        // 수동으로 업데이트 체크 트리거
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            logger.info("수동 업데이트 체크 시작")
            NSApp.activate(ignoringOtherApps: true)
            self.updaterController?.updater.checkForUpdates()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        appModel?.teardownOnTermination()
    }
}
