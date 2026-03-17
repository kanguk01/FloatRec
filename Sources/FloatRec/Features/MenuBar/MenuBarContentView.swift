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
                    Text("영역 선택 오버레이는 실녹화 엔진을 붙일 때 함께 연결합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                ProgressView()
                    .controlSize(.small)
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

                SettingsLink {
                    Text("설정")
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
