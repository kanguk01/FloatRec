import AppKit
import SwiftUI

@MainActor
final class ShelfWindowController {
    private var panel: NSPanel?

    func show(using model: AppModel) {
        let panel = panel ?? makePanel()
        panel.contentView = NSHostingView(
            rootView: ShelfContainerView()
                .environmentObject(model)
        )

        let clipCount = max(model.clips.count, 1)
        let height = min(560, CGFloat(clipCount) * 220 + 70)
        panel.setContentSize(NSSize(width: 340, height: height))
        position(panel: panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 240),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.animationBehavior = .utilityWindow
        return panel
    }

    private func position(panel: NSPanel) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelFrame = panel.frame
        let origin = NSPoint(
            x: screenFrame.maxX - panelFrame.width - 16,
            y: screenFrame.minY + 16
        )
        panel.setFrameOrigin(origin)
    }
}
