import SwiftUI

struct ShelfContainerView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FloatRec Shelf")
                        .font(.title3.weight(.semibold))
                    Text("녹화가 끝난 클립을 여기서 바로 드래그하거나 저장합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("모두 닫기") {
                    appModel.clearClips()
                }
                .disabled(appModel.clips.isEmpty)
            }

            if appModel.clips.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("아직 클립이 없습니다.")
                        .font(.headline)
                    Text("메뉴바나 단축키로 녹화를 시작한 뒤 종료하면 이 선반에 카드가 고정됩니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(appModel.clips) { clip in
                            RecordingClipCardView(clip: clip)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(18)
        .frame(width: 360)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.99, blue: 1.0),
                    Color(red: 0.91, green: 0.95, blue: 0.99),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}
