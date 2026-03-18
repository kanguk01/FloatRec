import SwiftUI

@main
struct FloatRecApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        MenuBarExtra("FloatRec", systemImage: appModel.statusItemSymbolName) {
            MenuBarContentView()
                .environmentObject(appModel)
                .onAppear {
                    appDelegate.appModel = appModel
                }
        }
        .menuBarExtraStyle(.window)
    }
}
