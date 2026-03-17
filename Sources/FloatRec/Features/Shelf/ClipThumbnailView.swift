import AppKit
import SwiftUI

struct ClipThumbnailView: View {
    @EnvironmentObject private var appModel: AppModel

    let clip: RecordingClip

    var body: some View {
        Button {
            appModel.openPreview(for: clip)
        } label: {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let thumbnail = appModel.thumbnail(for: clip) {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [
                                Color(red: 0.15, green: 0.22, blue: 0.33),
                                Color(red: 0.27, green: 0.46, blue: 0.69),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )

                        Image(systemName: "video")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white.opacity(0.88))
                    }
                }

                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.56),
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(alignment: .center) {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.45), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("미리보기")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(clip.formattedDuration)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(14)
            }
            .frame(height: 156)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(clip.isPostProcessing)
        .opacity(clip.isPostProcessing ? 0.78 : 1)
        .task(id: clip.id) {
            await appModel.loadThumbnailIfNeeded(for: clip)
        }
    }
}
