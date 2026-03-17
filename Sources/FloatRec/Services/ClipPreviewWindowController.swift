import AVKit
import AppKit
import SwiftUI

@MainActor
final class ClipPreviewWindowController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var player: AVPlayer?
    private var loopObserver: NSObjectProtocol?

    func show(clip: RecordingClip) {
        let panel = panel ?? makePanel()
        let player = AVPlayer(url: clip.fileURL)

        removeLoopObserver()
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }

        self.player = player

        panel.contentView = NSHostingView(
            rootView: ClipPreviewContentView(
                clip: clip,
                player: player
            )
        )
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        player.play()
        self.panel = panel
    }

    func windowWillClose(_ notification: Notification) {
        player?.pause()
        player = nil
        removeLoopObserver()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.delegate = self
        return panel
    }

    private func removeLoopObserver() {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
    }
}

private struct ClipPreviewContentView: View {
    let clip: RecordingClip
    let player: AVPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.title)
                    .font(.title3.weight(.semibold))
                Text(clip.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VideoPlayer(player: player)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )

            HStack {
                Text("Space로 재생/정지, 창 닫기로 복귀")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(18)
        .frame(minWidth: 760, minHeight: 520)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.99, blue: 1.0),
                    Color(red: 0.92, green: 0.96, blue: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}
