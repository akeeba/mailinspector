import SwiftUI

@main
struct MailInspectorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = InspectorSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(appDelegate.pendingImports)
        }
        Settings {
            SettingsView()
                .environment(settings)
        }
    }
}
