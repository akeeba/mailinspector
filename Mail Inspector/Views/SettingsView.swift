//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI

/// App preferences, organized into tabs the way Mail and Safari organize theirs.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                GeneralSettingsView()
            }
            Tab("Authentication", systemImage: "checkmark.shield") {
                AuthenticationSettingsView()
            }
            Tab("Junk Mail", systemImage: "exclamationmark.bubble") {
                JunkMailSettingsView()
            }
            Tab("AI Analysis", systemImage: "sparkles") {
                AIAnalysisSettingsView()
            }
        }
    }
}
