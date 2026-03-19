import AppKit
import SwiftUI

struct RecordingClipCardView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isHovered = false

    let clip: RecordingClip

    var body: some View {
        let card = VStack(alignment: .leading, spacing: 0) {
            ClipThumbnailView(clip: clip)

            VStack(alignment: .leading, spacing: 4) {
                Text(clip.sourceLabel)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(clip.formattedDuration)
                    if clip.isPostProcessing {
                        Text("·")
                        HStack(spacing: 3) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("처리 중")
                        }
                        .foregroundStyle(.orange)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if !clip.isPostProcessing {
                Divider()
                    .padding(.horizontal, 10)

                HStack(spacing: 2) {
                    actionButton("저장", icon: "arrow.down.circle") {
                        appModel.saveClip(clip)
                    }
                    actionButton("복사", icon: "doc.on.doc") {
                        appModel.copyClipToPasteboard(clip)
                    }
                    actionButton("Finder", icon: "folder") {
                        appModel.revealClipInFinder(clip)
                    }
                    actionButton("GIF", icon: "photo.on.rectangle") {
                        appModel.exportClipAsGIF(clip)
                    }

                    Spacer()

                    Button {
                        appModel.removeClip(clip)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovered = $0 }

        if clip.isPostProcessing {
            card
                .contextMenu {
                    Button("닫기") { appModel.removeClip(clip) }
                }
        } else {
            card
                .onDrag {
                    NSItemProvider(object: clip.fileURL as NSURL)
                }
                .contextMenu {
                    Button("미리보기") { appModel.openPreview(for: clip) }
                    Button("저장") { appModel.saveClip(clip) }
                    Button("Finder에서 보기") { appModel.revealClipInFinder(clip) }
                    Button("복사") { appModel.copyClipToPasteboard(clip) }
                    Button("GIF로 내보내기") { appModel.exportClipAsGIF(clip) }
                    Divider()
                    Button("닫기") { appModel.removeClip(clip) }
                }
        }
    }

    private func actionButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}
