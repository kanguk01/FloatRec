import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("FloatRec 설정")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                Label("녹화 시작/종료 단축키: \(appModel.hotKeyDisplayString)", systemImage: "keyboard")
                Label("녹화 종료 후 클립은 자동 저장하지 않고 임시 보관함에 유지", systemImage: "dock.rectangle")
                Label("디스플레이/윈도우 소스 목록은 ScreenCaptureKit에서 읽어옵니다", systemImage: "display.2")
                Label("자동 줌은 디스플레이/영역 녹화에서 후처리로 적용합니다", systemImage: "scope")
            }
            .font(.subheadline)

            Toggle(isOn: $appModel.featureFlags.isAutoZoomEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("커서 따라가는 자동 줌")
                    Text("녹화 종료 후 커서를 중심으로 부드럽게 확대된 결과물을 만듭니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Toggle(isOn: $appModel.featureFlags.isClickHighlightEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("클릭 리플 강조")
                    Text("클릭 순간에 주황색 리플을 얹어 사용자의 시선을 더 명확하게 유도합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("다음 단계")
                    .font(.headline)
                Text("윈도우 모드 후처리, Shelf 썸네일 미리보기, 공유 카드 고도화를 다음 단계로 연결할 예정입니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
}
