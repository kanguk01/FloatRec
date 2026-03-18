import AppKit
import Foundation
import os
@preconcurrency import ScreenCaptureKit

// MARK: - Result & Error Types

enum CaptureSelectionResult: @unchecked Sendable {
    case display(SCDisplay)
    case window(SCWindow)
    case area(AreaSelection)
}

enum CaptureSelectionError: LocalizedError {
    case cancelled
    case noDisplayAvailable
    case noWindowAvailable

    var errorDescription: String? {
        switch self {
        case .cancelled: "캡처 대상 선택이 취소되었습니다."
        case .noDisplayAvailable: "사용 가능한 디스플레이가 없습니다."
        case .noWindowAvailable: "선택한 위치에 윈도우가 없습니다."
        }
    }
}

// MARK: - Selection Mode

private enum SelectionMode: Int {
    case display = 0
    case window = 1
    case area = 2

    var label: String {
        switch self {
        case .display: "디스플레이"
        case .window: "윈도우"
        case .area: "영역"
        }
    }
}

// MARK: - Controller

@MainActor
final class CaptureSelectionOverlayController {
    private var windows: [CaptureSelectionWindow] = []
    private var continuation: CheckedContinuation<CaptureSelectionResult, Error>?
    private var hasCompleted = false

    private var cachedDisplays: [SCDisplay] = []
    private var cachedWindows: [SCWindow] = []
    private var cacheTimestamp: Date = .distantPast
    private let cacheValiditySeconds: TimeInterval = 120

    func selectCaptureSource() async throws -> CaptureSelectionResult {
        guard continuation == nil else {
            throw CaptureSelectionError.cancelled
        }

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            throw CaptureSelectionError.noDisplayAvailable
        }

        await refreshContentIfNeeded()

        guard !cachedDisplays.isEmpty else {
            throw CaptureSelectionError.noDisplayAvailable
        }

        let scDisplays = cachedDisplays
        let scWindows = cachedWindows

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.hasCompleted = false

            let mainScreen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens[0]

            self.windows = screens.map { screen in
                let isMainScreen = (screen.frame.origin == mainScreen.frame.origin)
                let window = CaptureSelectionWindow(
                    screen: screen,
                    isMainScreen: isMainScreen,
                    scDisplays: scDisplays,
                    scWindows: scWindows
                )
                window.selectionHandler = { [weak self] result in
                    self?.complete(with: result)
                }
                window.cancelHandler = { [weak self] in
                    self?.cancel()
                }
                window.modeChangeHandler = { [weak self] mode in
                    self?.broadcastModeChange(mode)
                }
                return window
            }

            windows.forEach { window in
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func cancelSelection() {
        cancel()
    }

    private func refreshContentIfNeeded() async {
        let isCacheValid = !cachedDisplays.isEmpty
            && Date().timeIntervalSince(cacheTimestamp) < cacheValiditySeconds

        if isCacheValid { return }

        // SCShareableContent can hang forever when the corecaptured daemon is stuck.
        // Use a continuation guarded by an atomic flag so only the first resolver wins.
        // The load runs as a detached task so we can abandon it on timeout.
        let content: SCShareableContent? = await withCheckedContinuation { continuation in
            let gate = OSAllocatedUnfairLock(initialState: false)

            Task.detached {
                let result = try? await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true
                )
                let shouldResume = gate.withLock { alreadyResumed -> Bool in
                    guard !alreadyResumed else { return false }
                    alreadyResumed = true
                    return true
                }
                if shouldResume {
                    continuation.resume(returning: result)
                }
            }

            Task.detached {
                try? await Task.sleep(for: .seconds(5))
                let shouldResume = gate.withLock { alreadyResumed -> Bool in
                    guard !alreadyResumed else { return false }
                    alreadyResumed = true
                    return true
                }
                if shouldResume {
                    continuation.resume(returning: nil)
                }
            }
        }

        if let content {
            cachedDisplays = content.displays
            cachedWindows = content.windows
            cacheTimestamp = Date()
        }
    }

    private func complete(with result: CaptureSelectionResult) {
        guard !hasCompleted else { return }
        hasCompleted = true
        teardown()
        continuation?.resume(returning: result)
        continuation = nil
    }

    private func cancel() {
        guard !hasCompleted else { return }
        hasCompleted = true
        teardown()
        continuation?.resume(throwing: CaptureSelectionError.cancelled)
        continuation = nil
    }

    private func broadcastModeChange(_ mode: SelectionMode) {
        for window in windows {
            (window.contentView as? CaptureSelectionOverlayView)?.applyMode(mode)
        }
    }

    private func teardown() {
        let windowsToRemove = windows
        windows.removeAll()
        windowsToRemove.forEach { window in
            window.selectionHandler = nil
            window.cancelHandler = nil
            window.modeChangeHandler = nil
            window.orderOut(nil)
        }
    }
}

// MARK: - Overlay Window

@MainActor
private final class CaptureSelectionWindow: NSWindow {
    var selectionHandler: ((CaptureSelectionResult) -> Void)?
    var cancelHandler: (() -> Void)?
    var modeChangeHandler: ((SelectionMode) -> Void)?

    init(
        screen: NSScreen,
        isMainScreen: Bool,
        scDisplays: [SCDisplay],
        scWindows: [SCWindow]
    ) {
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
        animationBehavior = .none
        acceptsMouseMovedEvents = true

        let overlayView = CaptureSelectionOverlayView(
            screen: screen,
            isMainScreen: isMainScreen,
            scDisplays: scDisplays,
            scWindows: scWindows
        )
        overlayView.selectionHandler = { [weak self] result in
            self?.selectionHandler?(result)
        }
        overlayView.cancelHandler = { [weak self] in
            self?.cancelHandler?()
        }
        overlayView.modeChangeHandler = { [weak self] mode in
            self?.modeChangeHandler?(mode)
        }

        contentView = overlayView
        initialFirstResponder = overlayView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Overlay View

@MainActor
private final class CaptureSelectionOverlayView: NSView {
    var selectionHandler: ((CaptureSelectionResult) -> Void)?
    var cancelHandler: (() -> Void)?
    var modeChangeHandler: ((SelectionMode) -> Void)?

    private let screen: NSScreen
    private let isMainScreen: Bool
    private let displayID: CGDirectDisplayID
    private let scDisplays: [SCDisplay]
    private let scWindows: [SCWindow]

    private var currentMode: SelectionMode = .display
    private var modeButtons: [SelectionMode: NSRect] = [:]

    // Window mode state
    private var highlightedWindowRect: NSRect?
    private var highlightedWindowID: CGWindowID?

    // Area mode state
    private var areaStartPoint: CGPoint?
    private var areaCurrentPoint: CGPoint?

    // Toolbar geometry
    private let toolbarWidth: CGFloat = 300
    private let toolbarHeight: CGFloat = 50
    private let toolbarBottomMargin: CGFloat = 80

    init(
        screen: NSScreen,
        isMainScreen: Bool,
        scDisplays: [SCDisplay],
        scWindows: [SCWindow]
    ) {
        self.screen = screen
        self.isMainScreen = isMainScreen
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        self.displayID = CGDirectDisplayID(screenNumber?.uint32Value ?? 0)
        self.scDisplays = scDisplays
        self.scWindows = scWindows
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Coordinate Conversion

    /// CG 좌표계(좌상단 원점)를 AppKit 좌표계(좌하단 원점)로 변환
    private func cgRectToNSRect(_ cgRect: CGRect) -> NSRect {
        let mainHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height ?? 0
        return NSRect(
            x: cgRect.origin.x,
            y: mainHeight - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )
    }

    /// 화면 전역 좌표를 이 뷰의 로컬 좌표로 변환
    private func globalToLocal(_ globalRect: NSRect) -> NSRect {
        let screenOrigin = screen.frame.origin
        return NSRect(
            x: globalRect.origin.x - screenOrigin.x,
            y: globalRect.origin.y - screenOrigin.y,
            width: globalRect.width,
            height: globalRect.height
        )
    }

    /// 마우스 뷰 로컬 좌표를 화면 전역 좌표로 변환
    private func localToGlobal(_ localPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: localPoint.x + screen.frame.origin.x,
            y: localPoint.y + screen.frame.origin.y
        )
    }

    // MARK: - Window Detection

    private func windowInfoList() -> [[String: Any]] {
        let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        let myPID = ProcessInfo.processInfo.processIdentifier
        return info.filter { dict in
            guard let pid = dict[kCGWindowOwnerPID as String] as? Int32, pid != myPID,
                  let bounds = dict[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = bounds["Width"], let h = bounds["Height"],
                  w >= 50, h >= 50,
                  let layer = dict[kCGWindowLayer as String] as? Int, layer == 0
            else {
                return false
            }
            return true
        }
    }

    /// 마우스 전역 좌표에 해당하는 최상위 윈도우 정보 반환
    private func topWindowAt(globalPoint: CGPoint) -> (CGWindowID, NSRect)? {
        let cgPoint = CGPoint(
            x: globalPoint.x,
            y: (NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height ?? 0) - globalPoint.y
        )

        for dict in windowInfoList() {
            guard let boundsDict = dict[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"], let y = boundsDict["Y"],
                  let w = boundsDict["Width"], let h = boundsDict["Height"],
                  let windowID = dict[kCGWindowNumber as String] as? CGWindowID
            else { continue }

            let cgRect = CGRect(x: x, y: y, width: w, height: h)
            if cgRect.contains(cgPoint) {
                let nsRect = cgRectToNSRect(cgRect)
                return (windowID, nsRect)
            }
        }
        return nil
    }

    // MARK: - Display Detection

    /// 이 뷰가 속한 화면의 SCDisplay 반환
    private func scDisplayForThisScreen() -> SCDisplay? {
        scDisplays.first(where: { $0.displayID == displayID })
    }

    /// 디스플레이 번호(1-based)
    private func displayIndex() -> Int {
        if let idx = scDisplays.firstIndex(where: { $0.displayID == displayID }) {
            return idx + 1
        }
        return 1
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        switch currentMode {
        case .display:
            drawDisplayMode(dirtyRect)
        case .window:
            drawWindowMode(dirtyRect)
        case .area:
            drawAreaMode(dirtyRect)
        }

        if isMainScreen {
            drawToolbar()
        }
    }

    private func drawDisplayMode(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        dirtyRect.fill()

        // 반투명 파란 테두리
        let borderInset: CGFloat = 4
        let borderRect = bounds.insetBy(dx: borderInset, dy: borderInset)
        NSColor.systemBlue.withAlphaComponent(0.6).setStroke()
        let borderPath = NSBezierPath(rect: borderRect)
        borderPath.lineWidth = 4
        borderPath.stroke()

        // 디스플레이 번호 중앙 표시
        let displayNum = "\(displayIndex())"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 64, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.8),
        ]
        let textSize = displayNum.size(withAttributes: attributes)
        let textOrigin = CGPoint(
            x: bounds.midX - textSize.width / 2,
            y: bounds.midY - textSize.height / 2
        )
        displayNum.draw(at: textOrigin, withAttributes: attributes)

        // 안내 텍스트
        let hint = "클릭하여 이 디스플레이 선택"
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
        ]
        let hintSize = hint.size(withAttributes: hintAttrs)
        let hintOrigin = CGPoint(
            x: bounds.midX - hintSize.width / 2,
            y: bounds.midY - textSize.height / 2 - hintSize.height - 12
        )
        hint.draw(at: hintOrigin, withAttributes: hintAttrs)
    }

    private func drawWindowMode(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        dirtyRect.fill()

        // 하이라이트된 윈도우 프레임 그리기
        if let highlightRect = highlightedWindowRect {
            let localRect = globalToLocal(highlightRect)

            // 하이라이트 영역 밝게
            NSColor.white.withAlphaComponent(0.08).setFill()
            localRect.fill()

            NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
            let path = NSBezierPath(rect: localRect)
            path.lineWidth = 3
            path.stroke()
        }

        // 안내 텍스트
        let hint = "윈도우 위에서 클릭하여 선택"
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
        ]
        let hintSize = hint.size(withAttributes: hintAttrs)
        let hintOrigin = CGPoint(
            x: bounds.midX - hintSize.width / 2,
            y: bounds.height - 60
        )
        hint.draw(at: hintOrigin, withAttributes: hintAttrs)
    }

    private func drawAreaMode(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.48).setFill()
        dirtyRect.fill()

        guard let selectionRect = areaSelectionRect else {
            drawCrosshair()
            return
        }

        // 선택 영역 외부를 어둡게, 내부는 투명하게
        let clipPath = NSBezierPath(rect: bounds)
        clipPath.append(NSBezierPath(rect: selectionRect))
        clipPath.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.52).setFill()
        clipPath.fill()

        // 선택 영역 테두리
        NSColor.white.setStroke()
        let path = NSBezierPath(rect: selectionRect)
        path.lineWidth = 2
        path.stroke()

        // 크기 레이블
        let sizeText = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = sizeText.size(withAttributes: attrs)
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
            withAttributes: attrs
        )
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

        let hint = "드래그해서 녹화할 영역을 선택하세요"
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
        ]
        let hintSize = hint.size(withAttributes: hintAttrs)
        let hintOrigin = CGPoint(
            x: bounds.midX - hintSize.width / 2,
            y: bounds.height - 60
        )
        hint.draw(at: hintOrigin, withAttributes: hintAttrs)
    }

    // MARK: - Toolbar Drawing

    private func drawToolbar() {
        let toolbarRect = toolbarFrame()

        // 배경 (어두운 반투명)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: toolbarRect, xRadius: 12, yRadius: 12).fill()

        // 미세한 테두리
        NSColor.white.withAlphaComponent(0.15).setStroke()
        let borderPath = NSBezierPath(roundedRect: toolbarRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        borderPath.lineWidth = 1
        borderPath.stroke()

        let buttonWidth = (toolbarWidth - 24) / 3
        let buttonHeight: CGFloat = 32
        let buttonY = toolbarRect.minY + (toolbarHeight - buttonHeight) / 2

        var newModeButtons: [SelectionMode: NSRect] = [:]

        for mode in [SelectionMode.display, .window, .area] {
            let buttonX = toolbarRect.minX + 12 + CGFloat(mode.rawValue) * buttonWidth
            let buttonRect = NSRect(x: buttonX, y: buttonY, width: buttonWidth, height: buttonHeight)
            newModeButtons[mode] = buttonRect

            if mode == currentMode {
                NSColor.white.withAlphaComponent(0.2).setFill()
                NSBezierPath(roundedRect: buttonRect, xRadius: 8, yRadius: 8).fill()
            }

            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: mode == currentMode ? .semibold : .regular),
                .foregroundColor: mode == currentMode
                    ? NSColor.white
                    : NSColor.white.withAlphaComponent(0.6),
            ]
            let text = mode.label
            let textSize = text.size(withAttributes: textAttrs)
            let textOrigin = CGPoint(
                x: buttonRect.midX - textSize.width / 2,
                y: buttonRect.midY - textSize.height / 2
            )
            text.draw(at: textOrigin, withAttributes: textAttrs)
        }

        modeButtons = newModeButtons

        // ESC 안내
        let escText = "ESC로 취소"
        let escAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.45),
        ]
        let escSize = escText.size(withAttributes: escAttrs)
        let escOrigin = CGPoint(
            x: toolbarRect.midX - escSize.width / 2,
            y: toolbarRect.minY - escSize.height - 8
        )
        escText.draw(at: escOrigin, withAttributes: escAttrs)
    }

    private func toolbarFrame() -> NSRect {
        NSRect(
            x: (bounds.width - toolbarWidth) / 2,
            y: toolbarBottomMargin,
            width: toolbarWidth,
            height: toolbarHeight
        )
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        // 툴바 버튼 클릭 확인
        if isMainScreen {
            for (mode, rect) in modeButtons {
                if rect.contains(location) {
                    switchMode(to: mode)
                    return
                }
            }
        }

        switch currentMode {
        case .display:
            handleDisplayClick()
        case .window:
            handleWindowClick(at: location)
        case .area:
            areaStartPoint = location
            areaCurrentPoint = location
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard currentMode == .area else { return }
        areaCurrentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard currentMode == .area else { return }
        areaCurrentPoint = convert(event.locationInWindow, from: nil)

        defer {
            areaStartPoint = nil
            areaCurrentPoint = nil
            needsDisplay = true
        }

        guard let rect = areaSelectionRect, rect.width >= 40, rect.height >= 40 else {
            return
        }

        // AppKit 좌표(좌하단 원점) → ScreenCaptureKit 좌표(좌상단 원점)로 변환
        let flippedRect = CGRect(
            x: rect.origin.x,
            y: bounds.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
        let selection = AreaSelection(displayID: displayID, rect: flippedRect)
        selectionHandler?(.area(selection))
    }

    override func mouseMoved(with event: NSEvent) {
        guard currentMode == .window else { return }

        let localPoint = convert(event.locationInWindow, from: nil)
        let globalPoint = localToGlobal(localPoint)

        if let (windowID, windowRect) = topWindowAt(globalPoint: globalPoint) {
            if highlightedWindowID != windowID {
                highlightedWindowID = windowID
                highlightedWindowRect = windowRect
                needsDisplay = true
            }
        } else {
            if highlightedWindowID != nil {
                highlightedWindowID = nil
                highlightedWindowRect = nil
                needsDisplay = true
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            cancelHandler?()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Tracking Areas

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    // MARK: - Selection Handlers

    private func handleDisplayClick() {
        guard let display = scDisplayForThisScreen() else { return }
        selectionHandler?(.display(display))
    }

    private func handleWindowClick(at localPoint: CGPoint) {
        let globalPoint = localToGlobal(localPoint)

        guard let (windowID, windowRect) = topWindowAt(globalPoint: globalPoint) else {
            return
        }

        // windowID로 직접 매칭
        if let scWindow = scWindows.first(where: { $0.windowID == windowID }) {
            selectionHandler?(.window(scWindow))
            return
        }

        // Electron 등 탭 전환 시 windowID가 바뀌므로 PID + 프레임으로 폴백 매칭
        let windowInfos = windowInfoList()
        guard let clickedInfo = windowInfos.first(where: {
            ($0[kCGWindowNumber as String] as? CGWindowID) == windowID
        }),
            let ownerPID = clickedInfo[kCGWindowOwnerPID as String] as? Int32
        else {
            return
        }

        let scWindow = scWindows
            .filter { $0.owningApplication?.processID == pid_t(ownerPID) }
            .min(by: { a, b in
                frameDifference(a.frame, windowRect) < frameDifference(b.frame, windowRect)
            })

        guard let scWindow else { return }
        selectionHandler?(.window(scWindow))
    }

    private func frameDifference(_ scFrame: CGRect, _ nsRect: NSRect) -> CGFloat {
        let mainHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height ?? 0
        let scNSRect = CGRect(
            x: scFrame.origin.x,
            y: mainHeight - scFrame.origin.y - scFrame.height,
            width: scFrame.width,
            height: scFrame.height
        )
        return abs(scNSRect.origin.x - nsRect.origin.x)
            + abs(scNSRect.origin.y - nsRect.origin.y)
            + abs(scNSRect.width - nsRect.width)
            + abs(scNSRect.height - nsRect.height)
    }

    func applyMode(_ newMode: SelectionMode) {
        guard newMode != currentMode else { return }
        currentMode = newMode
        highlightedWindowRect = nil
        highlightedWindowID = nil
        areaStartPoint = nil
        areaCurrentPoint = nil
        needsDisplay = true
    }

    private func switchMode(to newMode: SelectionMode) {
        applyMode(newMode)
        modeChangeHandler?(newMode)
    }

    // MARK: - Area Selection Geometry

    private var areaSelectionRect: CGRect? {
        guard let start = areaStartPoint, let current = areaCurrentPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        ).integral
    }
}
