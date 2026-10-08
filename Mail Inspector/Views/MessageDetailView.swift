import SwiftUI

/// The analysis view for a single imported message.
struct MessageDetailView: View {
    let message: EmailMessage
    @Environment(InspectorSettings.self) private var settings

    private var authenticationAnalysis: AuthenticationAnalysis {
        AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: settings.trustedAuthServIDs)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SenderIdentityView(message: message)
                Divider()
                AuthenticationView(analysis: authenticationAnalysis)
                Divider()
                RawHeadersView(message: message)
            }
            .padding()
        }
        .navigationTitle(message.subject ?? "(No Subject)")
    }
}
