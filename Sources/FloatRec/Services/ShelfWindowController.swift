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

        let targetSize = NSSize(width: 360, height: min(520, CGFloat(max(model.clips.count, 1)) * 142 + 88))
        panel.setContentSize(targetSize)
        position(panel: panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
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
        return panel
    }

    private func position(panel: NSPanel) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelFrame = panel.frame
        let origin = NSPoint(
            x: screenFrame.maxX - panelFrame.width - 20,
            y: screenFrame.minY + 20
        )

        panel.setFrameOrigin(origin)
    }
}
