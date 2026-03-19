import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(using model: AppModel) {
        let window = window ?? makeWindow()
        window.contentView = NSHostingView(
            rootView: SettingsView(onCheckForUpdates: {
                guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
                appDelegate.updaterController?.checkForUpdates(nil)
            })
                .environmentObject(model)
                .frame(width: 360, height: 320)
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FloatRec 설정"
        window.isReleasedWhenClosed = false
        return window
    }
}
