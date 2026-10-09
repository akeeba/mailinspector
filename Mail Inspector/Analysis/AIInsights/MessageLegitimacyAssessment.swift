//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import FoundationModels

/// Structured output for the on-device model's legitimacy assessment. Kept to just two fields —
/// its JSON schema is injected into the prompt on every call and counts against the on-device
/// model's 4096-token context window, so this stays as small as it can usefully be.
@available(macOS 27, *)
@Generable
struct MessageLegitimacyAssessment {
    @Guide(description: "How legitimate this message looks, from 0 (definitely forged or malicious) to 100 (definitely legitimate)", .range(0...100))
    var score: Int

    @Guide(description: "A concise, one-to-two sentence rationale for the score, naming the strongest signal(s) it relies on")
    var rationale: String
}
