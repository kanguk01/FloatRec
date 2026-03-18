import SwiftUI

struct ShelfContainerView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            if appModel.clips.isEmpty {
                emptyState
                    .padding(20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(appModel.clips) { clip in
                            RecordingClipCardView(clip: clip)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.automatic)
            }
        }
        .frame(width: 340)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack {
            Text("녹화 클립")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button {
                appModel.clearClips()
            } label: {
                Text("모두 지우기")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(appModel.clips.isEmpty)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("클립 없음")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
