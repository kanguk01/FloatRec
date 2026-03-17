import AppKit
import SwiftUI

struct RecordingClipCardView: View {
    @EnvironmentObject private var appModel: AppModel

    let clip: RecordingClip

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: fileIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .padding(10)
                    .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 5) {
                    Text(clip.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(clip.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(clip.isTemporary ? "저장 전까지 임시 보관" : "저장됨")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    appModel.removeClip(clip)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Button("저장") {
                    appModel.saveClip(clip)
                }

                ShareLink(item: clip.fileURL) {
                    Label("공유", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)

                Button("Finder") {
                    appModel.revealClipInFinder(clip)
                }

                Spacer()

                Text("드래그 가능")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.92),
                    Color(red: 0.93, green: 0.96, blue: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
        .onDrag {
            NSItemProvider(object: clip.fileURL as NSURL)
        }
        .contextMenu {
            Button("저장") {
                appModel.saveClip(clip)
            }

            Button("Finder에서 보기") {
                appModel.revealClipInFinder(clip)
            }

            Divider()

            Button("닫기") {
                appModel.removeClip(clip)
            }
        }
    }

    private var fileIcon: NSImage {
        NSWorkspace.shared.icon(forFile: clip.fileURL.path)
    }
}
