import SwiftUI

@main
struct FloatRecApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(appModel)
                .onAppear {
                    appDelegate.appModel = appModel
                }
        } label: {
            if appModel.recordingState.isRecording {
                HStack(spacing: 4) {
                    Image(nsImage: MenuBarIconRenderer.recording)
                    Text(appModel.formattedElapsedTime)
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                }
            } else if appModel.recordingState.isPaused {
                HStack(spacing: 4) {
                    Image(nsImage: MenuBarIconRenderer.paused)
                    Text("일시정지")
                        .font(.system(.caption, weight: .medium))
                }
            } else {
                Image(nsImage: MenuBarIconRenderer.idle)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

enum MenuBarIconRenderer {
    static let idle: NSImage = render(style: .idle)
    static let recording: NSImage = render(style: .recording)
    static let paused: NSImage = render(style: .paused)

    private enum Style { case idle, recording, paused }

    private static func render(style: Style) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 7.0

            NSColor.black.setStroke()

            let circle = NSBezierPath(ovalIn: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            ))
            circle.lineWidth = 1.4
            circle.stroke()

            let diamond = NSBezierPath()
            diamond.lineCapStyle = .round
            diamond.lineJoinStyle = .round
            diamond.lineWidth = 1.2
            let top = CGPoint(x: center.x, y: center.y + radius)
            let bottom = CGPoint(x: center.x, y: center.y - radius)
            let left = CGPoint(x: center.x - radius, y: center.y)
            let right = CGPoint(x: center.x + radius, y: center.y)
            diamond.move(to: top)
            diamond.line(to: right)
            diamond.move(to: right)
            diamond.line(to: bottom)
            diamond.move(to: bottom)
            diamond.line(to: left)
            diamond.move(to: left)
            diamond.line(to: top)
            diamond.stroke()

            switch style {
            case .recording:
                NSColor.black.setFill()
                let dotR: CGFloat = 2.2
                NSBezierPath(ovalIn: CGRect(
                    x: center.x - dotR, y: center.y - dotR,
                    width: dotR * 2, height: dotR * 2
                )).fill()
            case .paused:
                NSColor.black.setFill()
                let barW: CGFloat = 1.3
                let barH: CGFloat = 4.5
                let gap: CGFloat = 1.4
                NSBezierPath(rect: CGRect(x: center.x - gap - barW, y: center.y - barH / 2, width: barW, height: barH)).fill()
                NSBezierPath(rect: CGRect(x: center.x + gap, y: center.y - barH / 2, width: barW, height: barH)).fill()
            case .idle:
                break
            }

            return true
        }
        image.isTemplate = true
        return image
    }
}
