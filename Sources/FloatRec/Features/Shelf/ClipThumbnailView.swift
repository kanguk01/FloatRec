import AppKit
import SwiftUI

struct ClipThumbnailView: View {
    @EnvironmentObject private var appModel: AppModel

    let clip: RecordingClip

    var body: some View {
        Button {
            appModel.openPreview(for: clip)
        } label: {
            ZStack {
                Group {
                    if let thumbnail = appModel.thumbnail(for: clip) {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(nsColor: .controlBackgroundColor)
                        Image(systemName: "video")
                            .font(.system(size: 22))
                            .foregroundStyle(.tertiary)
                    }
                }

                // 재생 아이콘
                if !clip.isPostProcessing {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.4), in: Circle())
                }
            }
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(clip.isPostProcessing)
        .opacity(clip.isPostProcessing ? 0.6 : 1)
        .task(id: clip.id) {
            await appModel.loadThumbnailIfNeeded(for: clip)
        }
    }
}
