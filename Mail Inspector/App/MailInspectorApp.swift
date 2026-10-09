//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI

@main
struct MailInspectorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = InspectorSettings()
    @State private var fileOpenRequest = FileOpenRequest()
    @State private var reportExportRequest = ReportExportRequest()
    @State private var aiInsightsSessionCache = AIInsightsSessionCache()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(appDelegate.pendingImports)
                .environment(fileOpenRequest)
                .environment(reportExportRequest)
                .environment(aiInsightsSessionCache)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Mail Inspector") {
                    AboutPanel.show()
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open Email File…") {
                    fileOpenRequest.fire()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("Export Report as PDF…") {
                    reportExportRequest.fireExport()
                }
                .keyboardShortcut("e", modifiers: .command)
                Button("Share Report…") {
                    reportExportRequest.fireShare()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
        Settings {
            SettingsView()
                .environment(settings)
        }
    }
}
