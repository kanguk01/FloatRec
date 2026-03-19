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
                Label(appModel.formattedElapsedTime, systemImage: appModel.statusItemSymbolName)
            } else {
                Label("FloatRec", systemImage: appModel.statusItemSymbolName)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
