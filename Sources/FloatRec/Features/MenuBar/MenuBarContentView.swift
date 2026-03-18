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
                    Text(appModel.hotKeyDisplayString)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.thinMaterial, in: Capsule())

                    if appModel.recordingState.isRecording {
                        Text(appModel.stopHotKeyDisplayString)
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
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
                .disabled(appModel.recordingState.isBusy)

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
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(appModel.captureSelectionSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("녹화 시작을 누르면 선택기가 열리고, 클릭한 대상이 바로 녹화됩니다.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("단축키 녹화는 현재 선택된 대상을 바로 사용합니다.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Button {
                            appModel.presentCaptureTargetPicker()
                        } label: {
                            Label("미리 선택", systemImage: "cursorarrow.click")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appModel.recordingState.isBusy)

                        HStack {
                            if let selectedSource = appModel.selectedSourceOption {
                                Text(selectedSource.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text("호버로 강조된 대상을 클릭하면 바로 선택됩니다.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("새로고침") {
                                Task {
                                    await appModel.refreshCaptureSources(force: true)
                                }
                            }
                            .font(.caption)
                            .disabled(appModel.recordingState.isBusy || appModel.isRefreshingSources)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
                .disabled(appModel.recordingState.isRecording || appModel.recordingState.isBusy)

                Picker("카메라 제어 방식", selection: $appModel.featureFlags.cameraControlStyle) {
                    ForEach(CameraControlStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(
                    !appModel.featureFlags.isAutoZoomEnabled
                        || appModel.recordingState.isRecording
                        || appModel.recordingState.isBusy
                )

                if appModel.featureFlags.cameraControlStyle == .manualHotkeys,
                   appModel.featureFlags.isAutoZoomEnabled {
                    Toggle(isOn: $appModel.featureFlags.defaultManualSpotlightEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("기본 스포트라이트")
                            Text("녹화 시작 시 켜두고, 녹화 중에는 ⌃4로 바로 켜고 끕니다.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(appModel.recordingState.isRecording || appModel.recordingState.isBusy)
                }
            }

            HStack {
                Label(
                    appModel.featureFlags.isAutoZoomEnabled
                        ? (appModel.featureFlags.cameraControlStyle == .automatic ? "자동 줌 켜짐" : "수동 카메라 켜짐")
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

                if appModel.featureFlags.cameraControlStyle == .manualHotkeys,
                   appModel.featureFlags.isAutoZoomEnabled {
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

            if appModel.isRefreshingSources {
                Text("캡처 소스를 다시 불러오는 중입니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

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
