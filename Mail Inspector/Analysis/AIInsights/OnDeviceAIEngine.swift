//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation
import FoundationModels

/// Structured output for the on-device model's legitimacy assessment. Kept to just two fields —
/// its JSON schema is injected into the prompt on every call and counts against the on-device
/// model's 4096-token context window, so this stays as small as it can usefully be. Private to
/// this file on purpose: everything outside `OnDeviceAIEngine` depends on the plain,
/// always-available `AIScoreResult` instead, so the rest of the app never needs to know this
/// macOS-27-only type exists.
@available(macOS 27, *)
@Generable
private struct MessageLegitimacyAssessment {
    @Guide(description: "How legitimate this message looks, from 0 (definitely forged or malicious) to 100 (definitely legitimate)", .range(0...100))
    var score: Int

    @Guide(description: "A concise, one-to-two sentence rationale for the score, naming the strongest signal(s) it relies on")
    var rationale: String
}

/// Apple's on-device Apple Intelligence model, wrapped as an `AIAnalysisEngine`.
///
/// Uses two `LanguageModelSession`s, deliberately never one: a throwaway session for the single
/// structured-score call, and a long-lived one (`chatSession`) for the prefab analysis and every
/// chat turn after it. They're kept separate because sharing one session let the model imitate
/// its own earlier JSON-shaped score reply in later plain-text chat answers — a real,
/// user-reported bug, not a hypothetical one — confirmed and fixed via hands-on `RunCodeSnippet`
/// testing before this design was trusted.
///
/// Requires macOS 27, not 26: `LanguageModelError` (needed to describe failures) is only
/// available starting macOS 27 on this SDK, even though `LanguageModelSession`/`Generable`
/// themselves are available from macOS 26 — confirmed by the compiler, not documentation, so
/// this engine (and anything that constructs one) is gated at the stricter of the two.
@available(macOS 27, *)
@MainActor
final class OnDeviceAIEngine: AIAnalysisEngine {
    private let systemPrompt: String
    private let chatSession: LanguageModelSession

    init(systemPrompt: String) {
        self.systemPrompt = systemPrompt
        self.chatSession = LanguageModelSession(instructions: systemPrompt)
    }

    var capabilities: AIEngineCapabilities {
        AIEngineCapabilities(
            supportsStreaming: true,
            supportsModelListing: false,
            requiresApiKey: false,
            requiresEndpoint: false,
            supportsChat: true
        )
    }

    func generateScore(signalsSummary: String) async throws -> AIScoreResult {
        do {
            // A throwaway session, deliberately never reused for chat — see the type-level
            // comment for why mixing a structured-output exchange into the chat transcript
            // caused the model to imitate JSON in later plain-text replies.
            let scoringSession = LanguageModelSession(instructions: systemPrompt)
            let prompt = "Here is the computed signal digest for this email:\n\n\(signalsSummary)\n\nAssess how legitimate this message is."
            let response = try await scoringSession.respond(to: prompt, generating: MessageLegitimacyAssessment.self)
            return AIScoreResult(score: response.content.score, rationale: response.content.rationale)
        } catch {
            throw AIEngineError(message: Self.describeError(error))
        }
    }

    func streamRespond(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await snapshot in chatSession.streamResponse(to: prompt) {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AIEngineError(message: Self.describeError(error)))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func describeError(_ error: Error) -> String {
        guard let error = error as? LanguageModelError else {
            return "Something went wrong talking to Apple Intelligence."
        }
        switch error {
        case .guardrailViolation:
            return "Apple Intelligence's safety system blocked this request."
        case .refusal:
            return "The model declined to respond to this."
        case .contextSizeExceeded:
            return "This conversation has grown too long for the model to continue. Try asking a shorter question, or re-open the message to start fresh."
        case .rateLimited:
            return "Apple Intelligence is temporarily rate-limiting requests. Try again in a moment."
        case .unsupportedLanguageOrLocale:
            return "This content uses a language Apple Intelligence doesn't support here."
        case .timeout:
            return "Apple Intelligence took too long to respond."
        default:
            return "Apple Intelligence couldn't complete this request."
        }
    }
}
