import SwiftUI

struct ShelfContainerView: View {
    @EnvironmentObject private var appModel: AppModel
    var onMinimize: (() -> Void)?

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
        HStack(spacing: 8) {
            Text("녹화 클립")
                .font(.system(size: 13, weight: .semibold))

            Text("\(appModel.clips.count)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                onMinimize?()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("최소화")

            Button {
                appModel.clearClips()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(appModel.clips.isEmpty)
            .help("모두 닫기")
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
