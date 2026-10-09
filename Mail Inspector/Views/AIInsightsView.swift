//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI

/// The AI analysis section: an automatic 0-100 legitimacy gauge and short prose analysis (both
/// computed once per message, from `EmailSignalsSummary`'s signal digest only — never the raw
/// headers or body), plus a follow-up chat that reuses the same backend session so it can refer
/// back to the score and the analysis without re-explaining them. Carries no `@available`
/// annotation — which backend is active, and whether it's available right now, is entirely
/// `AIEngineFactory`'s concern.
struct AIInsightsView: View {
    let message: EmailMessage
    let authentication: AuthenticationAnalysis
    let deliveryPath: DeliveryPathAnalysis
    let senderIdentityObservations: [SecurityObservation]
    let spamAssessment: SpamLikelihoodAssessment?
    let allowIncludingMessageTextInChat: Bool

    @Environment(AIInsightsSessionCache.self) private var sessionCache
    @Environment(InspectorSettings.self) private var settings
    @State private var chatInput = ""
    @State private var includeMessageTextNextSend = false

    private var providerDisplayName: String {
        AIProviderCatalog.definition(for: settings.aiActiveProviderKey)?.name ?? "AI"
    }

    private var engineAvailability: AIEngineAvailability {
        AIEngineFactory.resolveActiveEngine(settings: settings, systemPrompt: settings.aiSystemPrompt)
    }

    /// Looked up (or created, on first access) through the shared cache, keyed by message id —
    /// this is what makes the score/analysis/chat survive switching to another message and back.
    /// `nil` only when no backend is currently usable (not configured, Apple Intelligence not
    /// enabled, missing endpoint/key/model, …).
    private var session: MessageInsightsSession? {
        if let existing = sessionCache.existingSession(for: message.id) {
            return existing
        }
        guard case .ready(let engine) = engineAvailability else { return nil }
        let summary = EmailSignalsSummary.build(
            message: message,
            authentication: authentication,
            deliveryPath: deliveryPath,
            senderIdentityObservations: senderIdentityObservations,
            spamAssessment: spamAssessment
        )
        return sessionCache.getOrCreateSession(for: message.id) {
            MessageInsightsSession(engine: engine, signalsSummary: summary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(providerDisplayName) Analysis")
                .font(.headline)

            if let session {
                content(session: session)
            } else if case .unavailable(let reason) = engineAvailability {
                AIInsightsUnavailableView(reason: reason)
            }
        }
        .task(id: message.id) {
            await session?.runInitialAnalysisIfNeeded()
        }
    }

    @ViewBuilder
    private func content(session: MessageInsightsSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.isRunningInitialAnalysis {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing with \(providerDisplayName)…")
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

/// Shown whenever no AI backend is currently usable — unsupported OS, Apple Intelligence not
/// enabled, ineligible hardware, or the model still downloading.
struct AIInsightsUnavailableView: View {
    let reason: String

    var body: some View {
        Label(reason, systemImage: "sparkles")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
