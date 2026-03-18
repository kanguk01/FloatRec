import AppKit
import Foundation

@MainActor
final class RecordingCameraHUDController {
    private var panel: NSPanel?
    private var titleLabel: NSTextField?
    private var detailLabel: NSTextField?
    private var hideTask: Task<Void, Never>?

    func showHint() {
        show(
            title: "수동 카메라 준비",
            detail: "⌃1 줌 · ⌃2 따라가기 · ⌃3 전체화면"
        )
    }

    func showState(title: String, detail: String) {
        show(title: title, detail: detail)
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
    }

    private func show(title: String, detail: String) {
        let panel = makePanelIfNeeded()
        titleLabel?.stringValue = title
        detailLabel?.stringValue = detail
        layout(panel: panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.25))
            guard let self else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            self.panel?.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.panel?.orderOut(nil)
            }
        })
    }
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 88),
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

        let visualEffectView = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 18
        visualEffectView.layer?.masksToBounds = true

        let titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .white

        let detailLabel = NSTextField(labelWithString: "")
        detailLabel.font = .systemFont(ofSize: 13, weight: .medium)
        detailLabel.textColor = NSColor.white.withAlphaComponent(0.82)

        let stack = NSStackView(views: [titleLabel, detailLabel])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.frame = visualEffectView.bounds
        stack.autoresizingMask = [.width, .height]

        visualEffectView.addSubview(stack)
        panel.contentView = visualEffectView

        self.panel = panel
        self.titleLabel = titleLabel
        self.detailLabel = detailLabel
        return panel
    }

    private func layout(panel: NSPanel) {
        guard let screen = screenForPresentation() else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let size = panel.frame.size
        let origin = CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - size.height - 54
        )
        panel.setFrameOrigin(origin)
    }

    private func screenForPresentation() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
    }
}
