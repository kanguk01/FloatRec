import SwiftUI

@main
struct FloatRecApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(appModel)
                .onAppear {
                    appDelegate.appModel = appModel
                }
        } label: {
            if appModel.recordingState.isRecording {
                Label(appModel.formattedElapsedTime, systemImage: "record.circle.fill")
            } else if appModel.recordingState.isPaused {
                Label("일시정지", systemImage: "pause.circle.fill")
            } else {
                Image(systemName: "circle.dashed")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
