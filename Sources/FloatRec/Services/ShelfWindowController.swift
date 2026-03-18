import AppKit
import SwiftUI

@MainActor
final class ShelfWindowController {
    private var panel: NSPanel?
    private var miniPanel: NSPanel?
    private var isMinimized = false
    private weak var appModel: AppModel?

    func show(using model: AppModel) {
        self.appModel = model

        if isMinimized {
            showMiniPanel(model: model)
            return
        }

        let panel = panel ?? makePanel()
        panel.contentView = NSHostingView(
            rootView: ShelfContainerView(onMinimize: { [weak self] in
                self?.minimize()
            })
            .environmentObject(model)
        )

        let clipCount = max(model.clips.count, 1)
        let height = min(640, CGFloat(clipCount) * 260 + 60)
        panel.setContentSize(NSSize(width: 340, height: height))
        position(panel: panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        miniPanel?.orderOut(nil)
        isMinimized = false
    }

    private func minimize() {
        panel?.orderOut(nil)
        isMinimized = true
        if let model = appModel {
            showMiniPanel(model: model)
        }
    }

    private func restore() {
        miniPanel?.orderOut(nil)
        isMinimized = false
        if let model = appModel {
            show(using: model)
        }
    }

    private func showMiniPanel(model: AppModel) {
        let mini = miniPanel ?? makeMiniPanel()
        mini.contentView = NSHostingView(
            rootView: ShelfMiniView(
                clipCount: model.clips.count,
                onRestore: { [weak self] in self?.restore() },
                onClose: { [weak self] in self?.hide(); model.clearClips() }
            )
        )
        mini.setContentSize(NSSize(width: 140, height: 36))
        positionMini(panel: mini)
        mini.orderFrontRegardless()
        self.miniPanel = mini
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

    private func makeMiniPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 140, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.isMovableByWindowBackground = true
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

    private func positionMini(panel: NSPanel) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelFrame = panel.frame
        let origin = NSPoint(
            x: screenFrame.maxX - panelFrame.width - 16,
            y: screenFrame.minY + 16
        )
        panel.setFrameOrigin(origin)
    }
}

private struct ShelfMiniView: View {
    let clipCount: Int
    let onRestore: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onRestore) {
                HStack(spacing: 5) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 11, weight: .medium))
                    Text("\(clipCount)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 16)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .frame(height: 36)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}
