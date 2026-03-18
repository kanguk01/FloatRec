import AppKit
import Foundation

@MainActor
final class AreaSelectionOverlayController {
    private var windows: [AreaSelectionWindow] = []
    private var continuation: CheckedContinuation<AreaSelection, Error>?
    private var hasCompletedSelection = false

    func selectArea() async throws -> AreaSelection {
        guard continuation == nil else {
            throw AreaSelectionError.invalidSelection
        }

        let availableScreens = NSScreen.screens
        guard !availableScreens.isEmpty else {
            throw AreaSelectionError.unavailableScreen
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.hasCompletedSelection = false
            self.windows = availableScreens.map { screen in
                let window = AreaSelectionWindow(screen: screen)
                window.selectionHandler = { [weak self] selection in
                    self?.complete(with: selection)
                }
                window.cancelHandler = { [weak self] in
                    self?.cancel()
                }
                return window
            }

            windows.forEach { window in
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func complete(with selection: AreaSelection) {
        guard !hasCompletedSelection else {
            return
        }

        hasCompletedSelection = true
        teardown()
        continuation?.resume(returning: selection)
        continuation = nil
    }

    private func cancel() {
        guard !hasCompletedSelection else {
            return
        }

        hasCompletedSelection = true
        teardown()
        continuation?.resume(throwing: AreaSelectionError.cancelled)
        continuation = nil
    }

    private func teardown() {
        windows.forEach { window in
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }
}

@MainActor
private final class AreaSelectionWindow: NSWindow {
    var selectionHandler: ((AreaSelection) -> Void)?
    var cancelHandler: (() -> Void)?

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        setFrame(screen.frame, display: true)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        hasShadow = false

        let overlayView = AreaSelectionOverlayView(screen: screen)
        overlayView.selectionHandler = { [weak self] selection in
            self?.selectionHandler?(selection)
        }
        overlayView.cancelHandler = { [weak self] in
            self?.cancelHandler?()
        }

        contentView = overlayView
        initialFirstResponder = overlayView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private final class AreaSelectionOverlayView: NSView {
    var selectionHandler: ((AreaSelection) -> Void)?
    var cancelHandler: (() -> Void)?

    private let displayID: CGDirectDisplayID
    private let instructionField = NSTextField(labelWithString: "드래그해서 녹화할 영역을 선택하세요. ESC로 취소")
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    init(screen: NSScreen) {
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        self.displayID = CGDirectDisplayID(screenNumber?.uint32Value ?? 0)
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true

        instructionField.font = .systemFont(ofSize: 16, weight: .semibold)
        instructionField.textColor = .white
        instructionField.backgroundColor = NSColor.black.withAlphaComponent(0.45)
        instructionField.drawsBackground = true
        instructionField.isBordered = false
        instructionField.lineBreakMode = .byTruncatingTail
        instructionField.alignment = .center
        addSubview(instructionField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        instructionField.frame = CGRect(x: 28, y: bounds.height - 72, width: min(420, bounds.width - 56), height: 36)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.48).setFill()
        dirtyRect.fill()

        guard let selectionRect else {
            drawCrosshair()
            return
        }

        let clipPath = NSBezierPath(rect: bounds)
        clipPath.append(NSBezierPath(rect: selectionRect))
        clipPath.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.52).setFill()
        clipPath.fill()

        NSColor.white.setStroke()
        let path = NSBezierPath(rect: selectionRect)
        path.lineWidth = 2
        path.stroke()

        let sizeText = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = sizeText.size(withAttributes: attributes)
        let pillRect = CGRect(
            x: selectionRect.minX,
            y: max(14, selectionRect.maxY + 10),
            width: textSize.width + 18,
            height: 28
        )
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: 14, yRadius: 14).fill()
        sizeText.draw(
            at: CGPoint(x: pillRect.minX + 9, y: pillRect.minY + 7),
            withAttributes: attributes
        )
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        startPoint = location
        currentPoint = location
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        defer {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
        }

        guard let selectionRect, selectionRect.width >= 40, selectionRect.height >= 40 else {
            cancelHandler?()
            return
        }

        let selection = AreaSelection(
            displayID: displayID,
            rect: selectionRect
        )
        selectionHandler?(selection)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancelHandler?()
        } else {
            super.keyDown(with: event)
        }
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else {
            return nil
        }

        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        ).integral
    }

    private func drawCrosshair() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = NSBezierPath()
        path.move(to: CGPoint(x: center.x - 18, y: center.y))
        path.line(to: CGPoint(x: center.x + 18, y: center.y))
        path.move(to: CGPoint(x: center.x, y: center.y - 18))
        path.line(to: CGPoint(x: center.x, y: center.y + 18))
        path.lineWidth = 2
        NSColor.white.withAlphaComponent(0.7).setStroke()
        path.stroke()
    }
}
