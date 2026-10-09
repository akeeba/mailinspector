//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI

/// The Apple Intelligence section: an automatic 0-100 legitimacy gauge and short prose analysis
/// (both computed once per message, from `EmailSignalsSummary`'s signal digest only — never the
/// raw headers or body), plus a follow-up chat that reuses the same on-device session so it can
/// refer back to the score and the analysis without re-explaining them.
@available(macOS 27, *)
struct AIInsightsView: View {
    let message: EmailMessage
    let authentication: AuthenticationAnalysis
    let deliveryPath: DeliveryPathAnalysis
    let senderIdentityObservations: [SecurityObservation]
    let spamAssessment: SpamLikelihoodAssessment?
    let allowIncludingMessageTextInChat: Bool

    @Environment(AIInsightsSessionCache.self) private var sessionCache
    @State private var chatInput = ""
    @State private var includeMessageTextNextSend = false

    /// Looked up (or created, on first access) through the shared cache, keyed by message id —
    /// this is what makes the score/analysis/chat survive switching to another message and back.
    private var session: MessageInsightsSession {
        let summary = EmailSignalsSummary.build(
            message: message,
            authentication: authentication,
            deliveryPath: deliveryPath,
            senderIdentityObservations: senderIdentityObservations,
            spamAssessment: spamAssessment
        )
        let object = sessionCache.getOrCreateSession(for: message.id) {
            MessageInsightsSession(signalsSummary: summary)
        }
        // Invariant: only this view ever stores a session under a message id, and it always
        // stores a `MessageInsightsSession`.
        return object as! MessageInsightsSession
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple Intelligence Analysis")
                .font(.headline)

            switch AIInsightsAvailability.current {
            case .unavailable(let reason):
                AIInsightsUnavailableView(reason: reason)
            case .available:
                content
            }
        }
        .task(id: message.id) {
            guard AIInsightsAvailability.current == .available else { return }
            await session.runInitialAnalysisIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        let session = session
        VStack(alignment: .leading, spacing: 12) {
            if session.isRunningInitialAnalysis {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing with Apple Intelligence…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let assessment = session.assessment {
                HStack(alignment: .top, spacing: 16) {
                    Gauge(value: Double(assessment.score), in: 0...100) {
                        Text("Legitimacy")
                    } currentValueLabel: {
                        Text("\(assessment.score)%")
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(tintColor(for: assessment.score))
                    .accessibilityLabel("Legitimacy score: \(qualitativeLabel(for: assessment.score)), \(assessment.score) percent")

                    VStack(alignment: .leading, spacing: 4) {
                        Text(qualitativeLabel(for: assessment.score))
                            .font(.body.weight(.medium))
                        Text(assessment.rationale)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let prefabAnalysis = session.prefabAnalysis {
                Text(prefabAnalysis)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            if let lastError = session.lastError, session.assessment == nil {
                Label(lastError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("An AI opinion, not a verdict — it can be confidently wrong. Always weigh it against the signals above.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()
            chatSection(session: session)
        }
    }

    @ViewBuilder
    private func chatSection(session: MessageInsightsSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask a Question")
                .font(.subheadline.weight(.semibold))

            if !session.chatMessages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(session.chatMessages) { chatMessage in
                        ChatBubble(message: chatMessage)
                    }
                }
            }

            if allowIncludingMessageTextInChat {
                Toggle("Include message text in next question", isOn: $includeMessageTextNextSend)
                    .font(.caption)
                    .toggleStyle(.checkbox)
            }

            HStack(alignment: .bottom) {
                TextField("Ask about this message's headers and signals…", text: $chatInput, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendChatMessage(session: session) }
                Button("Send") { sendChatMessage(session: session) }
                    .disabled(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isSendingChatMessage)
            }
            if session.isSendingChatMessage {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func sendChatMessage(session: MessageInsightsSession) {
        let text = chatInput
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        chatInput = ""
        let excerpt = includeMessageTextNextSend ? MessageBodyTextExtractor.excerpt(for: message) : nil
        includeMessageTextNextSend = false
        Task {
            await session.sendChatMessage(text, bodyExcerpt: excerpt)
        }
    }

    private func tintColor(for score: Int) -> Color {
        switch score {
        case ..<33: return .red
        case ..<66: return .orange
        default: return .green
        }
    }

    private func qualitativeLabel(for score: Int) -> String {
        switch score {
        case ..<33: return "Likely forged"
        case ..<66: return "Uncertain"
        default: return "Likely legitimate"
        }
    }
}

@available(macOS 27, *)
private struct ChatBubble: View {
    let message: MessageInsightsSession.ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(.callout)
                .textSelection(.enabled)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(message.role == .user ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                )
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

/// Shown whenever Apple Intelligence isn't available — unsupported OS, not enabled, ineligible
/// hardware, or the model still downloading. Carries no `@available` annotation (unlike the rest
/// of this file) so `MessageDetailView` can also show it directly on macOS versions below the
/// feature's actual floor, where `AIInsightsView` itself can't even be referenced.
struct AIInsightsUnavailableView: View {
    let reason: String

    var body: some View {
        Label(reason, systemImage: "sparkles")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
