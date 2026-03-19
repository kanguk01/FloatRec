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

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("녹화")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(appModel.hotKeyDisplayString)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())

                    if appModel.recordingState.isRecording || appModel.recordingState.isPaused {
                        HStack(spacing: 4) {
                            Text("종료")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text(appModel.stopHotKeyDisplayString)
                                .font(.system(.caption2, design: .rounded, weight: .medium))
                        }

                        HStack(spacing: 4) {
                            Text(appModel.recordingState.isPaused ? "재개" : "일시정지")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.orange)
                            Text(appModel.pauseHotKeyDisplayString)
                                .font(.system(.caption2, design: .rounded, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("카메라")
                    .font(.subheadline.weight(.semibold))

                Toggle(isOn: $appModel.featureFlags.isAutoZoomEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("카메라 후처리")
                        Text("녹화 결과에 확대와 이동을 적용합니다.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .disabled(appModel.recordingState.isRecording || appModel.recordingState.isPaused || appModel.recordingState.isBusy)

                if appModel.featureFlags.isAutoZoomEnabled {
                    Toggle(isOn: $appModel.featureFlags.defaultManualSpotlightEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("기본 스포트라이트")
                            Text("녹화 시작 시 켜두고, 녹화 중에는 ⌃4로 바로 켜고 끕니다.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(appModel.recordingState.isRecording || appModel.recordingState.isPaused || appModel.recordingState.isBusy)

                    Toggle(isOn: $appModel.featureFlags.isLivePreviewEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("실시간 프리뷰")
                            Text("녹화 중 줌, 스포트라이트 효과를 화면에 미리 표시합니다.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(appModel.recordingState.isRecording || appModel.recordingState.isPaused || appModel.recordingState.isBusy)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("오디오")
                    .font(.subheadline.weight(.semibold))

                Toggle(isOn: $appModel.featureFlags.isSystemAudioEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("시스템 사운드")
                        Text("앱에서 재생되는 소리를 녹화합니다.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .disabled(appModel.recordingState.isRecording || appModel.recordingState.isBusy)

                Toggle(isOn: $appModel.featureFlags.isMicrophoneEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("마이크")
                        Text("마이크 입력을 함께 녹화합니다.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .disabled(appModel.recordingState.isRecording || appModel.recordingState.isBusy)
            }

            HStack {
                Label(
                    appModel.featureFlags.isAutoZoomEnabled
                        ? "수동 카메라 켜짐"
                        : "카메라 후처리 꺼짐",
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

                if appModel.featureFlags.isAutoZoomEnabled {
                    Text("⌃4 스포트라이트")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.yellow.opacity(0.12), in: Capsule())
                        .foregroundStyle(.yellow)
                }

                Spacer()
            }

            Text(appModel.cameraControlSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let installMessage = appModel.installRecommendationMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(installMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)

                    HStack {
                        Button("응용 프로그램") {
                            appModel.openApplicationsFolder()
                        }

                        Button("현재 앱 보기") {
                            appModel.revealRunningApp()
                        }
                    }
                    .font(.caption)
                }
                .padding(10)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 8) {
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
                .tint(appModel.recordingState.isRecording ? .red : appModel.recordingState.isPaused ? .orange : .accentColor)
                .disabled(appModel.recordingState.isBusy)

                if appModel.recordingState.isRecording {
                    Button {
                        Task {
                            await appModel.pauseRecording()
                        }
                    } label: {
                        Label("일시정지", systemImage: "pause.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }

                if appModel.recordingState.isPaused {
                    Button {
                        Task {
                            await appModel.stopRecording()
                        }
                    } label: {
                        Label("종료", systemImage: "stop.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }

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
                    Text(latestClip.sourceLabel)
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

                        if appModel.shouldRecommendApplicationsInstall {
                            Button("응용 프로그램") {
                                appModel.openApplicationsFolder()
                            }
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
    }
}
