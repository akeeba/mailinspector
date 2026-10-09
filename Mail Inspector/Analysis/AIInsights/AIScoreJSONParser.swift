//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// Extracts `{"score": 0-100, "rationale": "..."}` from a remote model's plain-text reply to the
/// score prompt — the stand-in for Apple's native `@Generable` structured output, which no other
/// provider has. Shared across every wire dialect, since asking for (and parsing) this JSON
/// shape is this app's own convention layered on top of whichever dialect actually sent the
/// prompt, not something that varies by wire format.
nonisolated enum AIScoreJSONParser {
    static func parse(_ text: String) throws -> AIScoreResult {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            if let firstNewline = trimmed.firstIndex(of: "\n") {
                trimmed = String(trimmed[trimmed.index(after: firstNewline)...])
            }
            if let fenceStart = trimmed.range(of: "```", options: .backwards) {
                trimmed = String(trimmed[..<fenceStart.lowerBound])
            }
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end else {
            throw AIEngineError(message: "The provider's response wasn't in the expected format.")
        }
        guard let data = String(trimmed[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scoreNumber = json["score"] as? NSNumber,
              let rationale = json["rationale"] as? String else {
            throw AIEngineError(message: "The provider's response wasn't in the expected format.")
        }
        let clampedScore = max(0, min(100, scoreNumber.intValue))
        return AIScoreResult(score: clampedScore, rationale: rationale)
    }
}
