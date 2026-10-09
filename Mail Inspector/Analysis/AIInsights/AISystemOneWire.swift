//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// Pure request-building and response-parsing for TypeSafe.ai's System One API's `noul` question
/// primitive (docs.typesafe.ai/primitives/noul) — one yes/no question, answered with a float
/// probability of "yes". Deliberately not an `AIWireDialectHandler` conformer: that protocol is
/// shaped around chat history, a single reply string, and SSE streaming, none of which this
/// request/response shape has. Kept free of `URLSession`/`SystemOneAIEngine` state so it's
/// testable without a network call.
nonisolated enum AISystemOneWire {
    /// The one `noul` question this app ever asks — its id is purely an internal label picked out
    /// of the `answers` map in the reply, never shown to the user.
    static let questionKey = "legitimacy"

    /// `criteria` isn't exposed as a separate Settings field (the task only calls for one editable
    /// "Prompt"), but giving the model a concrete true/false split alongside that prompt measurably
    /// improves discrimination — see `.claude/docs/system-one-jev.md` for the tuning notes.
    static let criteriaTrue = "SPF/DKIM/DMARC pass and align with the claimed sender, there are no [warning]-tagged delivery-path or sender-identity lines, and any spam-filter score is low. Routine [notable]/[info]-tagged lines don't count against this."
    static let criteriaFalse = "SPF/DKIM/DMARC fail or misalign with the claimed sender, there's a [warning]-tagged delivery-path or sender-identity line, or a spam-filter score is elevated."

    static func requestBody(prompt: String, signalsSummary: String, contextLength: Int?) -> [String: Any] {
        var body: [String: Any] = [
            "state": signalsSummary,
            "model": "jev-latest",
            "questions": [
                questionKey: [
                    "type": "noul",
                    "instructions": prompt,
                    "criteria": ["true": criteriaTrue, "false": criteriaFalse],
                ],
            ],
        ]
        // Not part of TypeSafe's own documented request shape — sent only for self-hosted/
        // alternative System One-compatible services that need to be told their context window.
        // Omitted entirely at 0 (and always for Jev itself, which never sets this on the engine).
        if let contextLength, contextLength > 0 {
            body["context_length"] = contextLength
        }
        return body
    }

    /// Non-streaming response shape: `{"answers": {"<questionKey>": {"type": "noul", "noul": 0.93}}}`,
    /// or an error body on failure. Returns the legitimacy score already rescaled to 0-100.
    static func parseScore(_ data: Data) throws -> Int {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIEngineError(message: "The provider returned a response this app couldn't understand.")
        }
        if let errorObject = json["error"] as? [String: Any], let message = errorObject["message"] as? String {
            throw AIEngineError(message: message)
        }
        guard let answers = json["answers"] as? [String: Any],
              let answer = answers[questionKey] as? [String: Any],
              let noulNumber = answer["noul"] as? NSNumber else {
            throw AIEngineError(message: "The provider's response didn't include a legitimacy answer.")
        }
        let clampedNoul = max(0.0, min(1.0, noulNumber.doubleValue))
        return Int((clampedNoul * 100).rounded())
    }
}
