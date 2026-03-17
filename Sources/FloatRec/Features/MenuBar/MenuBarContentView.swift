import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FloatRec")
                        .font(.headline)
                    Text("상태: \(appModel.recordingState.statusText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(appModel.hotKeyDisplayString)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("캡처 대상")
                    .font(.subheadline.weight(.semibold))

                Picker("캡처 모드", selection: $appModel.captureMode) {
                    ForEach(CaptureMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(appModel.captureMode.helperText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appModel.captureMode == .area {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(appModel.captureSelectionSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("녹화 시작 후 전체 화면에 오버레이가 뜨고, 드래그를 마치면 바로 녹화가 시작됩니다.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                } else if appModel.currentSourceOptions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("캡처 소스를 아직 불러오지 못했습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("소스 새로고침") {
                            Task {
                                await appModel.refreshCaptureSources(force: true)
                            }
                        }
                        .disabled(appModel.isRefreshingSources)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Picker("대상", selection: sourceSelectionBinding) {
                        ForEach(appModel.currentSourceOptions) { source in
                            VStack(alignment: .leading) {
                                Text(source.title).tag(source.id)
                            }
                        }
                    }
                    .labelsHidden()

                    HStack {
                        Text(appModel.captureSelectionSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("새로고침") {
                            Task {
                                await appModel.refreshCaptureSources(force: true)
                            }
                        }
                        .font(.caption)
                        .disabled(appModel.isRefreshingSources)
                    }
                }
            }

            HStack {
                Label(
                    appModel.featureFlags.isAutoZoomEnabled ? "자동 줌 켜짐" : "자동 줌 꺼짐",
                    systemImage: "scope"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if appModel.featureFlags.isClickHighlightEnabled {
                    Text("클릭 강조")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                        .foregroundStyle(.orange)
                }

                Spacer()
            }

            Button {
                Task {
                    await appModel.toggleRecording()
                }
            } label: {
                Label(
                    appModel.recordingState.primaryActionTitle,
                    systemImage: appModel.recordingState.primaryActionSymbolName
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(appModel.recordingState.isRecording ? .red : .accentColor)
            .disabled(appModel.recordingState.isBusy)

            if appModel.recordingState.isBusy {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView()
                        .controlSize(.small)

                    if case .processing = appModel.recordingState,
                       appModel.featureFlags.isAutoZoomEnabled || appModel.featureFlags.isClickHighlightEnabled {
                        Text("커서 추적 기반 후처리 결과물을 정리 중입니다.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let latestClip = appModel.latestClip {
                VStack(alignment: .leading, spacing: 6) {
                    Text("최근 클립")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(latestClip.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(latestClip.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            if let errorMessage = appModel.lastErrorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)

                    HStack {
                        Button("설정 열기") {
                            appModel.openScreenRecordingSettings()
                        }

                        Button("닫기") {
                            appModel.clearError()
                        }
                    }
                    .font(.caption)
                }
                .padding(10)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            Divider()

            HStack {
                Button("보관함 열기") {
                    appModel.showShelf()
                }
                .disabled(appModel.clips.isEmpty)

                Button("설정") {
                    appModel.openSettingsWindow()
                }

                Spacer()

                Button("종료") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .font(.subheadline)
        }
        .padding(16)
        .frame(width: 320)
        .task {
            await appModel.refreshCaptureSourcesIfNeeded()
        }
    }

    private var sourceSelectionBinding: Binding<String> {
        Binding(
            get: { appModel.selectedSourceID ?? appModel.currentSourceOptions.first?.id ?? "" },
            set: { appModel.selectedSourceID = $0 }
        )
    }
}
