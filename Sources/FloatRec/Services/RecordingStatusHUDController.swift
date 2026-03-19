import AppKit
import Foundation

@MainActor
final class RecordingStatusHUDController {
    static let shared = RecordingStatusHUDController()

    private var panel: NSPanel?
    private var timeLabel: NSTextField?
    private var statusLabel: NSTextField?
    private var shortcutsLabel: NSTextField?
    private var cameraLabel: NSTextField?
    private var dotView: NSView?

    private var lastElapsed = "0:00"
    private var lastIsPaused = false

    func update(elapsed: String, isPaused: Bool) {
        lastElapsed = elapsed
        lastIsPaused = isPaused

        let panel = makePanelIfNeeded()
        timeLabel?.stringValue = elapsed
        dotView?.layer?.backgroundColor = isPaused
            ? NSColor.systemOrange.cgColor
            : NSColor.systemRed.cgColor

        statusLabel?.stringValue = isPaused ? "일시정지" : "녹화 중"

        shortcutsLabel?.stringValue = isPaused
            ? "⌘⇧P 재개 · ⌘⇧0 종료"
            : "⌘⇧P 일시정지 · ⌘⇧0 종료"

        layout(panel: panel)
        panel.orderFrontRegardless()
    }

    func updateCameraStatus(_ text: String) {
        _ = makePanelIfNeeded()
        cameraLabel?.stringValue = text
    }

    func clearCameraStatus() {
        cameraLabel?.stringValue = ""
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private init() {}

    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }

        let panelHeight: CGFloat = 56
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.sharingType = .none
        panel.animationBehavior = .none

        let card = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: panelHeight))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.85).cgColor
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        card.autoresizingMask = [.width, .height]

        let dot = NSView(frame: NSRect(x: 12, y: 30, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        card.addSubview(dot)

        let time = NSTextField(labelWithString: "0:00")
        time.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        time.textColor = .white
        time.frame = NSRect(x: 28, y: 30, width: 54, height: 20)
        card.addSubview(time)

        let status = NSTextField(labelWithString: "녹화 중")
        status.font = .systemFont(ofSize: 10, weight: .medium)
        status.textColor = .white.withAlphaComponent(0.55)
        status.frame = NSRect(x: 84, y: 32, width: 60, height: 14)
        card.addSubview(status)

        let shortcuts = NSTextField(labelWithString: "")
        shortcuts.font = .systemFont(ofSize: 10, weight: .regular)
        shortcuts.textColor = .white.withAlphaComponent(0.4)
        shortcuts.lineBreakMode = .byTruncatingTail
        shortcuts.frame = NSRect(x: 148, y: 32, width: 200, height: 14)
        card.addSubview(shortcuts)

        let camera = NSTextField(labelWithString: "")
        camera.font = .systemFont(ofSize: 10, weight: .medium)
        camera.textColor = NSColor(calibratedRed: 0.6, green: 0.88, blue: 1.0, alpha: 0.9)
        camera.lineBreakMode = .byTruncatingTail
        camera.frame = NSRect(x: 12, y: 8, width: 336, height: 14)
        card.addSubview(camera)

        panel.contentView = card
        self.panel = panel
        self.dotView = dot
        self.timeLabel = time
        self.statusLabel = status
        self.shortcutsLabel = shortcuts
        self.cameraLabel = camera
        return panel
    }

    private func layout(panel: NSPanel) {
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSEvent.mouseLocation)
        }) ?? NSScreen.main else { return }

        let visibleFrame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - size.height - 10
        ))
    }
}
