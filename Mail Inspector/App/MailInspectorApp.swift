//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI

@main
struct MailInspectorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = InspectorSettings()
    @State private var fileOpenRequest = FileOpenRequest()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(appDelegate.pendingImports)
                .environment(fileOpenRequest)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Email File…") {
                    fileOpenRequest.fire()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
        Settings {
            SettingsView()
                .environment(settings)
        }
    }
}
