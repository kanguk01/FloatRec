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
                Label("자동 줌과 클릭 강조는 디스플레이/윈도우/영역 녹화에서 후처리로 적용합니다", systemImage: "scope")
            }
            .font(.subheadline)

            Toggle(isOn: $appModel.featureFlags.isAutoZoomEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("카메라 후처리")
                    Text("자동 추적 또는 수동 키 제어로 확대/이동이 적용된 결과물을 만듭니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Picker("카메라 제어 방식", selection: $appModel.featureFlags.cameraControlStyle) {
                ForEach(CameraControlStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!appModel.featureFlags.isAutoZoomEnabled)

            Text(appModel.cameraControlSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

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
                Text("수동 카메라 키 흐름과 자동 추적 흐름을 더 자연스럽게 다듬는 작업이 다음 단계입니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
}
