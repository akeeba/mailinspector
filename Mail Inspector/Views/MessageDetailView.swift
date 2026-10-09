//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI

/// The analysis view for a single imported message.
struct MessageDetailView: View {
    let message: EmailMessage
    @Environment(InspectorSettings.self) private var settings

    private var senderIdentityAnalysis: SenderIdentityAnalysis {
        SenderIdentityAnalyzer.analyze(message: message)
    }

    private var authenticationAnalysis: AuthenticationAnalysis {
        AuthenticationAnalyzer.analyze(
            message: message,
            trustedAuthServIDs: settings.trustedAuthServIDs,
            trustAllByDefault: settings.trustAllAuthenticationResultsByDefault
        )
    }

    private var deliveryPathAnalysis: DeliveryPathAnalysis {
        DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: settings.trustedAuthServIDs)
    }

    private var additionalHeaders: [AdditionalSecurityHeader] {
        SecurityHeaderCatalog.presentHeaders(in: message.parsed)
    }

    private var spfRecheckTarget: SPFRecheckTarget? {
        SPFRecheckTargetResolver.resolve(message: message, authentication: authenticationAnalysis)
    }

    private var spamAssessment: SpamLikelihoodAssessment? {
        guard settings.trustServerSpamHeaders else { return nil }
        return SpamLikelihoodAnalyzer.assess(parsed: message.parsed)
    }

    /// Combines every analyzer's observations into one list with a single, non-colliding set of
    /// identifiers.
    private var combinedObservations: [SecurityObservation] {
        (senderIdentityAnalysis.observations + deliveryPathAnalysis.observations)
            .enumerated()
            .map { index, observation in
                SecurityObservation(id: index, severity: observation.severity, title: observation.title, detail: observation.detail)
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ObservationsSummaryView(observations: combinedObservations)
                SenderIdentityView(message: message)
                Divider()
                AuthenticationView(analysis: authenticationAnalysis, spfRecheckTarget: spfRecheckTarget)
                if let spamAssessment {
                    Divider()
                    SpamLikelihoodView(assessment: spamAssessment)
                }
                Divider()
                DeliveryPathView(analysis: deliveryPathAnalysis)
                if !additionalHeaders.isEmpty {
                    Divider()
                    AdditionalSecurityHeadersView(headers: additionalHeaders)
                }
                Divider()
                RawHeadersView(message: message)
            }
            .padding()
        }
        .navigationTitle(message.subject ?? "(No Subject)")
    }
}
