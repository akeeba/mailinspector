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
    /// Removes this message from the sidebar — wired to Backspace/Delete so the report stays
    /// keyboard-navigable without requiring focus to be back on the sidebar list first.
    let onDelete: () -> Void
    @Environment(InspectorSettings.self) private var settings
    @Environment(AIInsightsSessionCache.self) private var aiInsightsSessionCache
    @State private var scrollPosition = ScrollPosition()
    @State private var scrollMetrics = ScrollMetrics()

    /// Tracked so arrow/page/home/end key handling knows how far it can scroll.
    private struct ScrollMetrics: Equatable {
        var offsetY: CGFloat = 0
        var containerHeight: CGFloat = 0
        var contentHeight: CGFloat = 0
    }

    private let arrowScrollStep: CGFloat = 60

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

    private enum ReportSection: Hashable {
        case observations
        case senderIdentity
        case authentication
        case spam
        case deliveryPath
        case aiInsights
        case additionalHeaders
        case rawHeaders
    }

    /// Reads through the cache (not a local `@State`) so this reflects the real,
    /// possibly-still-in-flight `MessageInsightsSession` for this exact message, and so
    /// `SummaryBlocksView`'s AI block updates automatically once the score is ready — the
    /// `.assessment?.score` read below is itself what makes this view's body depend on that
    /// `@Observable` session, however it was obtained.
    private var aiLegitimacyScore: Int? {
        guard settings.isAIInsightsEnabled else { return nil }
        guard #available(macOS 27, *) else { return nil }
        guard case .available = AIInsightsAvailability.current else { return nil }
        return (aiInsightsSessionCache.existingSession(for: message.id) as? MessageInsightsSession)?.assessment?.score
    }

    /// True once the feature is on and available, as long as there's no score yet and no
    /// failure — covers both "the session hasn't been created yet" (it will be, momentarily,
    /// once `AIInsightsView` appears below) and "it exists but the score is still generating",
    /// so the summary block can show a spinner immediately rather than waiting for
    /// `AIInsightsView` to mount first.
    private var aiScoreIsPending: Bool {
        guard settings.isAIInsightsEnabled else { return false }
        guard #available(macOS 27, *) else { return false }
        guard case .available = AIInsightsAvailability.current else { return false }
        guard let session = aiInsightsSessionCache.existingSession(for: message.id) as? MessageInsightsSession else {
            return true
        }
        if session.assessment != nil { return false }
        if session.lastError != nil { return false }
        return true
    }

    @FocusState private var focusedSection: ReportSection?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if settings.isObservationsSummaryEnabled, !combinedObservations.isEmpty {
                        ObservationsSummaryView(observations: combinedObservations)
                            .focusable()
                            .focused($focusedSection, equals: .observations)
                            .id(ReportSection.observations)
                    }
                    SenderIdentityView(
                        message: message,
                        dmarcVerdict: authenticationAnalysis.dmarc.verdict,
                        spamAssessment: spamAssessment,
                        brandImagesEnabled: settings.showBrandImages,
                        hideBrandImagesForMessagesWithoutSpamScore: settings.hideBrandImagesForMessagesWithoutSpamScore,
                        hideBrandImagesAboveSpamThreshold: settings.hideBrandImagesAboveSpamThreshold
                    )
                        .focusable()
                        .focused($focusedSection, equals: .senderIdentity)
                        .id(ReportSection.senderIdentity)
                    SummaryBlocksView(
                        authentication: authenticationAnalysis,
                        deliveryPath: deliveryPathAnalysis,
                        spamAssessment: spamAssessment,
                        aiScore: aiLegitimacyScore,
                        aiScoreIsPending: aiScoreIsPending,
                        onTapAuthentication: { scrollTo(.authentication, proxy: proxy) },
                        onTapHops: { scrollTo(.deliveryPath, proxy: proxy) },
                        onTapSpam: { scrollTo(.spam, proxy: proxy) },
                        onTapAI: { scrollTo(.aiInsights, proxy: proxy) }
                    )
                    Divider()
                    AuthenticationView(analysis: authenticationAnalysis, spfRecheckTarget: spfRecheckTarget)
                        .focusable()
                        .focused($focusedSection, equals: .authentication)
                        .id(ReportSection.authentication)
                    if let spamAssessment {
                        Divider()
                        SpamLikelihoodView(assessment: spamAssessment)
                            .focusable()
                            .focused($focusedSection, equals: .spam)
                            .id(ReportSection.spam)
                    }
                    Divider()
                    DeliveryPathView(analysis: deliveryPathAnalysis)
                        .focusable()
                        .focused($focusedSection, equals: .deliveryPath)
                        .id(ReportSection.deliveryPath)
                    if settings.isAIInsightsEnabled {
                        Divider()
                        Group {
                            if #available(macOS 27, *) {
                                AIInsightsView(
                                    message: message,
                                    authentication: authenticationAnalysis,
                                    deliveryPath: deliveryPathAnalysis,
                                    senderIdentityObservations: senderIdentityAnalysis.observations,
                                    spamAssessment: spamAssessment,
                                    allowIncludingMessageTextInChat: settings.allowIncludingMessageTextInAIChat
                                )
                            } else {
                                AIInsightsUnavailableView(reason: "Requires macOS 27 or later.")
                            }
                        }
                        .focusable()
                        .focused($focusedSection, equals: .aiInsights)
                        .id(ReportSection.aiInsights)
                    }
                    if !additionalHeaders.isEmpty {
                        Divider()
                        AdditionalSecurityHeadersView(headers: additionalHeaders)
                            .focusable()
                            .focused($focusedSection, equals: .additionalHeaders)
                            .id(ReportSection.additionalHeaders)
                    }
                    Divider()
                    RawHeadersView(message: message)
                        .focusable()
                        .focused($focusedSection, equals: .rawHeaders)
                        .id(ReportSection.rawHeaders)
                }
                .padding()
            }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                ScrollMetrics(
                    offsetY: geometry.contentOffset.y,
                    containerHeight: geometry.containerSize.height,
                    contentHeight: geometry.contentSize.height
                )
            } action: { _, newValue in
                scrollMetrics = newValue
            }
            .onKeyPress(.upArrow) { scrollBy(-arrowScrollStep); return .handled }
            .onKeyPress(.downArrow) { scrollBy(arrowScrollStep); return .handled }
            .onKeyPress(.pageUp) { scrollBy(-max(scrollMetrics.containerHeight, 1)); return .handled }
            .onKeyPress(.pageDown) { scrollBy(max(scrollMetrics.containerHeight, 1)); return .handled }
            .onKeyPress(.home) { scrollToEdge(.top); return .handled }
            .onKeyPress(.end) { scrollToEdge(.bottom); return .handled }
            .onDeleteCommand(perform: onDelete)
            .onChange(of: focusedSection) { _, newValue in
                guard let newValue else { return }
                scrollTo(newValue, proxy: proxy)
            }
        }
        .navigationTitle(message.subject ?? "(No Subject)")
    }

    private func scrollTo(_ section: ReportSection, proxy: ScrollViewProxy) {
        withAnimation {
            proxy.scrollTo(section, anchor: .top)
        }
    }

    private func scrollBy(_ delta: CGFloat) {
        let maxY = max(0, scrollMetrics.contentHeight - scrollMetrics.containerHeight)
        let newY = min(maxY, max(0, scrollMetrics.offsetY + delta))
        withAnimation {
            scrollPosition.scrollTo(y: newY)
        }
    }

    private func scrollToEdge(_ edge: Edge) {
        withAnimation {
            scrollPosition.scrollTo(edge: edge)
        }
    }
}
