import AppKit
import Foundation

struct CameraPreviewState {
    let zoomStep: Int
    let isFollowing: Bool
    let isSpotlightEnabled: Bool
    let anchorPoint: CGPoint?

    static let idle = CameraPreviewState(zoomStep: 0, isFollowing: false, isSpotlightEnabled: false, anchorPoint: nil)
}

@MainActor
final class CameraPreviewOverlayController {
    private static let zoomFactors: [CGFloat] = [1.0, 1.22, 1.4, 1.62, 1.86]

    private var panel: NSPanel?
    private var previewView: CameraPreviewView?

    func show(trackingRect: CGRect) {
        hide()

        let previewView = CameraPreviewView(trackingRect: trackingRect)
        previewView.frame = NSRect(origin: .zero, size: trackingRect.size)

        let panel = NSPanel(
            contentRect: trackingRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.setFrame(trackingRect, display: true)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.sharingType = .none
        panel.contentView = previewView

        self.panel = panel
        self.previewView = previewView

        panel.orderFrontRegardless()
        previewView.startTimer()
    }

    func hide() {
        previewView?.stopTimer()
        panel?.orderOut(nil)
        panel = nil
        previewView = nil
    }

    func update(state: CameraPreviewState, cursorLocation: CGPoint) {
        previewView?.currentState = state
        previewView?.needsDisplay = true
    }
}

private final class CameraPreviewView: NSView {
    private static let zoomFactors: [CGFloat] = [1.0, 1.22, 1.4, 1.62, 1.86]
    private static let spotlightDiameter: CGFloat = 300

    var currentState: CameraPreviewState = .idle
    private let trackingRect: CGRect
    private var cursorInView: CGPoint = .zero
    private var displayTimer: Timer?

    init(trackingRect: CGRect) {
        self.trackingRect = trackingRect
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func startTimer() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.updateCursorPosition()
            }
        }
    }

    func stopTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func updateCursorPosition() {
        let globalLocation = NSEvent.mouseLocation
        guard let window else { return }

        let windowLocation = CGPoint(
            x: globalLocation.x - window.frame.origin.x,
            y: globalLocation.y - window.frame.origin.y
        )
        cursorInView = windowLocation
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        defer { context.restoreGState() }

        let cursor = cursorInView
        let zoomCenter: CGPoint
        if currentState.isFollowing {
            zoomCenter = cursor
        } else if let anchor = currentState.anchorPoint {
            zoomCenter = anchor
        } else {
            zoomCenter = cursor
        }

        if currentState.isSpotlightEnabled, currentState.zoomStep > 0 {
            drawSpotlight(in: context, cursor: cursor)
        }

        if currentState.zoomStep > 0 {
            drawZoomFrame(in: context, center: zoomCenter)
        }

        if currentState.isFollowing, currentState.zoomStep > 0 {
            drawFollowIndicator(in: context, cursor: cursor)
        }
    }

    private func drawZoomFrame(in context: CGContext, center: CGPoint) {
        let zoomStep = min(currentState.zoomStep, Self.zoomFactors.count - 1)
        let zoomFactor = Self.zoomFactors[zoomStep]
        guard zoomFactor > 1.001 else { return }

        let visibleWidth = bounds.width / zoomFactor
        let visibleHeight = bounds.height / zoomFactor

        let originX = clamp(
            center.x - visibleWidth / 2,
            min: 0,
            max: bounds.width - visibleWidth
        )
        let originY = clamp(
            center.y - visibleHeight / 2,
            min: 0,
            max: bounds.height - visibleHeight
        )

        let zoomRect = CGRect(x: originX, y: originY, width: visibleWidth, height: visibleHeight)

        let outerPath = CGMutablePath()
        outerPath.addRect(bounds)
        outerPath.addRoundedRect(in: zoomRect, cornerWidth: 6, cornerHeight: 6)

        context.addPath(outerPath)
        context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        context.fillPath(using: .evenOdd)

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(1.5)
        let roundedRect = CGPath(roundedRect: zoomRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(roundedRect)
        context.strokePath()

        let label = String(format: "%.1fx", zoomFactor)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        ]
        let labelSize = label.size(withAttributes: attributes)
        let pillPadding: CGFloat = 5
        let pillWidth = labelSize.width + pillPadding * 2
        let pillHeight = labelSize.height + pillPadding
        let pillX = zoomRect.maxX - pillWidth - 6
        let pillY = zoomRect.minY + 6
        let pillRect = CGRect(x: pillX, y: pillY, width: pillWidth, height: pillHeight)

        context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        let pillPath = CGPath(roundedRect: pillRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(pillPath)
        context.fillPath()

        let textOrigin = CGPoint(x: pillX + pillPadding, y: pillY + pillPadding / 2)
        label.draw(at: textOrigin, withAttributes: attributes)
    }

    private func drawSpotlight(in context: CGContext, cursor: CGPoint) {
        let diameter = Self.spotlightDiameter
        let ellipseRect = CGRect(
            x: cursor.x - diameter / 2,
            y: cursor.y - diameter / 2,
            width: diameter,
            height: diameter
        )

        let fullPath = CGMutablePath()
        fullPath.addRect(bounds)
        fullPath.addEllipse(in: ellipseRect)

        context.addPath(fullPath)
        context.setFillColor(NSColor.black.withAlphaComponent(0.3).cgColor)
        context.fillPath(using: .evenOdd)
    }

    private func drawFollowIndicator(in context: CGContext, cursor: CGPoint) {
        let indicatorOffset: CGFloat = 20
        let centerX = cursor.x + indicatorOffset
        let centerY = cursor.y + indicatorOffset

        let armLength: CGFloat = 8
        let lineWidth: CGFloat = 1.5

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(lineWidth)

        // Horizontal crosshair arm
        context.move(to: CGPoint(x: centerX - armLength, y: centerY))
        context.addLine(to: CGPoint(x: centerX + armLength, y: centerY))
        context.strokePath()

        // Vertical crosshair arm
        context.move(to: CGPoint(x: centerX, y: centerY - armLength))
        context.addLine(to: CGPoint(x: centerX, y: centerY + armLength))
        context.strokePath()

        // Arrow tips on horizontal ends
        let arrowSize: CGFloat = 3
        // Left arrow
        context.move(to: CGPoint(x: centerX - armLength, y: centerY))
        context.addLine(to: CGPoint(x: centerX - armLength + arrowSize, y: centerY + arrowSize))
        context.move(to: CGPoint(x: centerX - armLength, y: centerY))
        context.addLine(to: CGPoint(x: centerX - armLength + arrowSize, y: centerY - arrowSize))
        context.strokePath()

        // Right arrow
        context.move(to: CGPoint(x: centerX + armLength, y: centerY))
        context.addLine(to: CGPoint(x: centerX + armLength - arrowSize, y: centerY + arrowSize))
        context.move(to: CGPoint(x: centerX + armLength, y: centerY))
        context.addLine(to: CGPoint(x: centerX + armLength - arrowSize, y: centerY - arrowSize))
        context.strokePath()
    }

    private func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}
