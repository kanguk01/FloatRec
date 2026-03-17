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
                Label("현재 빌드는 Shelf UX와 공유 흐름을 우선 검증하는 초기 버전", systemImage: "hammer")
            }
            .font(.subheadline)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("다음 단계")
                    .font(.headline)
                Text("실녹화 엔진, 영역 선택 오버레이, 커서 추적, 자동 줌을 순차적으로 연결할 예정입니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
}
