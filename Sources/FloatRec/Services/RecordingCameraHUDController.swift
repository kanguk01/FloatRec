import AppKit
import Foundation

@MainActor
final class RecordingCameraHUDController {
    private var panel: NSPanel?
    private var cardView: NSView?
    private var titleLabel: NSTextField?
    private var detailLabel: NSTextField?

    func showStatus(title: String, detail: String) {
        show(title: title, detail: detail)
    }

    func showHint(detail: String) {
        show(title: "수동 카메라", detail: detail)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func show(title: String, detail: String) {
        let panel = makePanelIfNeeded()
        titleLabel?.stringValue = title
        detailLabel?.stringValue = detail
        layout(panel: panel)
        if panel.alphaValue < 1 {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 94),
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

        let rootView = NSView(frame: panel.contentView?.bounds ?? .zero)
        rootView.autoresizingMask = [.width, .height]
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.clear.cgColor

        let cardView = NSView(frame: rootView.bounds)
        cardView.autoresizingMask = [.width, .height]
        cardView.wantsLayer = true
        cardView.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 0.92).cgColor
        cardView.layer?.cornerRadius = 22
        cardView.layer?.borderWidth = 1
        cardView.layer?.borderColor = NSColor(calibratedRed: 0.35, green: 0.84, blue: 0.98, alpha: 0.55).cgColor
        rootView.addSubview(cardView)

        let titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail

        let detailLabel = NSTextField(labelWithString: "")
        detailLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        detailLabel.textColor = NSColor(calibratedRed: 0.70, green: 0.92, blue: 1.0, alpha: 0.98)
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 2

        let stack = NSStackView(views: [titleLabel, detailLabel])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.frame = cardView.bounds
        stack.autoresizingMask = [.width, .height]
        stack.alignment = .leading

        cardView.addSubview(stack)
        panel.contentView = rootView

        self.panel = panel
        self.cardView = cardView
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
            x: visibleFrame.maxX - size.width - 26,
            y: visibleFrame.maxY - size.height - 28
        )
        panel.setFrameOrigin(origin)
    }

    private func screenForPresentation() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
    }
}
