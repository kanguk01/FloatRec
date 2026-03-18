import AppKit
import Foundation

@MainActor
final class DisplayHighlightController {
    private var highlightWindows: [CGDirectDisplayID: NSWindow] = [:]

    func showHighlight(for displayID: CGDirectDisplayID, label: String) {
        hideAll()

        guard let screen = NSScreen.screens.first(where: {
            let screenNumber = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return screenNumber?.uint32Value == displayID
        }) else {
            return
        }

        let window = makeHighlightWindow(for: screen, label: label)
        highlightWindows[displayID] = window
        window.orderFrontRegardless()
    }

    func hideAll() {
        highlightWindows.values.forEach { $0.orderOut(nil) }
        highlightWindows.removeAll()
    }

    private func makeHighlightWindow(for screen: NSScreen, label: String) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.setFrame(screen.frame, display: true)
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.animationBehavior = .none

        let view = DisplayHighlightView(label: label)
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        window.contentView = view
        return window
    }
}

private final class DisplayHighlightView: NSView {
    private let label: String

    init(label: String) {
        self.label = label
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemBlue.withAlphaComponent(0.08).setFill()
        dirtyRect.fill()

        let borderPath = NSBezierPath(rect: bounds.insetBy(dx: 4, dy: 4))
        borderPath.lineWidth = 8
        NSColor.systemBlue.withAlphaComponent(0.6).setStroke()
        borderPath.stroke()

        let text = label
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 72, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        let pillSize = CGSize(width: textSize.width + 60, height: textSize.height + 30)
        let pillOrigin = CGPoint(
            x: bounds.midX - pillSize.width / 2,
            y: bounds.midY - pillSize.height / 2
        )
        let pillRect = CGRect(origin: pillOrigin, size: pillSize)

        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: 24, yRadius: 24).fill()

        text.draw(
            at: CGPoint(x: pillRect.minX + 30, y: pillRect.minY + 15),
            withAttributes: attributes
        )
    }
}
