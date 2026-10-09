# Jev / System One-compatible score-only provider

A fourth AI-analysis backend, alongside On-Device Apple Intelligence, the on-device MLX models,
and the chat-capable remote catalogue (LM Studio, OpenAI, Anthropic, ...): TypeSafe.ai's System
One API ("Jev"), or any self-hosted/alternative service speaking the same wire shape (e.g. Laya
(local), Clef (local, online)). Two entries in `AIProviderCatalog`, both `kind: .systemOne`:

- **Jev** (`key: "jev"`) — TypeSafe's own hosted endpoint, fixed, API key required.
- **System One (Jev) compatible** (`key: "systemone_compatible"`) — user-provided endpoint, API
  key optional (same "bare local server" posture as LM Studio/Custom), plus a context-length
  field for self-hosted runtimes that need to be told their context window.

Picker order: Disabled, On-Device Apple Intelligence, Jev, System One compatible, the on-device
MLX models, LM Studio, the rest of the hosted catalogue, Custom.

**Why this exists**: System One answers a single yes/no question (the `noul` primitive —
docs.typesafe.ai/primitives/noul) with a float probability, in one fast round trip — no chat, no
conversation state, no prose generation. It's a genuinely different shape from every other
provider in the catalogue, all of which are chat-completions-style backends this app layers a
score-JSON convention on top of (see `build-progress.md`). That's why it's its own
`AIProviderKind` case and its own engine (`SystemOneAIEngine`), not another `AIWireDialect`
plugged into `RemoteAIEngine`/`AIWireDialectHandler` — that protocol's shape (history, a single
reply string, SSE) doesn't fit a one-shot float answer at all.

## Wire shape

Confirmed against `docs.typesafe.ai` (primitives/noul, introduction/quickstart, api.md) on
2026-10-09:

- `POST <endpoint>`, `Authorization: Bearer <key>`, JSON body:
  ```json
  {
    "state": "<the signal digest — same EmailSignalsSummary text every other provider gets>",
    "model": "jev-latest",
    "questions": {
      "legitimacy": {
        "type": "noul",
        "instructions": "<the per-provider Prompt from Settings>",
        "criteria": {"true": "...", "false": "..."}
      }
    }
  }
  ```
- Response: `{"answers": {"legitimacy": {"type": "noul", "noul": 0.93}}}` — rescaled to a 0-100
  score (`Int((noul * 100).rounded())`, clamped).
- Documented error statuses: 401 (bad/missing key), 422 (validation), 429 (rate limit), 529
  (overloaded). `SystemOneAIEngine` maps all four to a user-facing message, same pattern as
  `RemoteAIEngine.validateHTTPResponse`.
- `criteria` isn't a Settings-exposed field — it's a fixed true/false split
  (`AISystemOneWire.criteriaTrue/criteriaFalse`) sent alongside the editable `instructions`
  prompt, included because it measurably helped the model discriminate during manual testing (see
  below). Only one user-facing "Prompt" field exists, per the feature request.

### `context_length` — not part of TypeSafe's own API

TypeSafe's docs (api.md, concepts/system-one.md) document no `context_length` parameter, no
notion of self-hosting, and no named "System One compatible" services — those are entirely this
app's own generalization, modeled on how `AIProviderCatalog` already treats LM Studio/Custom as
"OpenAI-compatible" even though OpenAI's own docs don't describe them. The assumption: a
self-hosted/alternative runtime implementing this same request shape may need to be told its
context window the way local OpenAI-compatible servers often do (`n_ctx` and similar). This app
sends it as a top-level `"context_length": <int>` field, **only** for the editable-endpoint
("System One compatible") provider and only when the configured value is greater than 0 — never
for Jev itself, whose fixed hosted endpoint ignores it. If a real compatible service expects a
different field name or placement, adjust `AISystemOneWire.requestBody` — this is a guess, not a
confirmed spec.

## Manual verification

Run live against the real Jev endpoint, using whatever key was entered through the app's own
Settings UI (Preferences → AI Analysis → Jev → API key) — see `SystemOneLiveTests`, which reads
the key back via `AIKeychainStore.get(forProvider: "jev")` and skips entirely when none is
configured (`.enabled(if:)`), so it never hardcodes or requires a secret in the repo. The same
suite has a second, independently-skipped test for a configured "System One compatible" endpoint
(read from `UserDefaults`'s `aiProviderEndpoints["systemone_compatible"]`), for testing against a
local service like Laya once one is available.

- 2026-10-09, first pass: ran `SystemOneLiveTests.jevDiscriminatesLegitimateFromForged` against
  the real Jev endpoint with a user-supplied API key (saved through the app's own Settings UI,
  never seen by this repo). The test's own fixtures used paraphrased English ("no anomalies")
  rather than `EmailSignalsSummary`'s real digest format, so it passed (~0.65s) without actually
  exercising production behavior.
- 2026-10-09, in-app follow-up: the user tried Jev against real messages and reported it
  "very pessimistic about legitimacy." Root cause: `EmailSignalsSummary.build` tags every
  delivery-path/sender-identity line with a severity — `[notable]`/`[info]`/`[warning]` — and
  deliberately uses `[notable]` for routine, harmless patterns (an unresolvable reverse-DNS
  hostname, a message relayed through a sender's own SaaS infrastructure — see
  `DeliveryPathAnalyzer`). The original prompt/criteria said any "anomaly" counted against
  legitimacy with no severity distinction, so completely ordinary multi-hop mail — the overwhelming
  majority of real-world legitimate mail — got pulled down by flags the rest of this app
  intentionally treats as non-issues.
  - Fix: `SystemOneAIEngine.defaultPrompt` and `AISystemOneWire.criteriaTrue/criteriaFalse` now
    explicitly call out the `[notable]`/`[info]` vs. `[warning]` distinction — only `[warning]`
    lines, failing/misaligned authentication, or a high spam score should count against
    legitimacy.
  - Rewrote the live-test fixtures to match `EmailSignalsSummary`'s actual output (including a
    `[notable]` hop and sender-identity line in the "legitimate" fixture, specifically to catch a
    regression of this exact bug) and tightened the assertions from a bare `>` to
    `legitimate.score >= 60` / `forged.score <= 40`. Re-ran against the real endpoint: passed
    (~0.83s), confirming the recalibrated prompt no longer penalizes routine, low-severity flags.
  - The System One (Jev) compatible path (Laya/Clef or similar) is still untested — no such
    service was available in this session; its live test
    (`systemOneCompatibleDiscriminatesLegitimateFromForged`) stays skipped until one is configured,
    and may need its own prompt tuning if the service's underlying model behaves differently from
    Jev.

## Chat-capability gating

`AIEngineCapabilities` gained `supportsChat` (false only for `SystemOneAIEngine`). This is what
lets `MessageInsightsSession.runInitialAnalysisIfNeeded()` skip the second (prose-analysis)
network call entirely for this engine, and what lets `AIInsightsView` hide its chat section
without either of them needing to special-case the provider kind directly — they just ask the
engine's own capabilities. `AIAnalysisSettingsView` hides "Allow including message text in chat"
and the shared System Prompt editor (which is never sent anywhere for this engine — see its own
per-provider Prompt field instead) the same way, keyed off `provider.kind == .systemOne`.

`AIInsightsExportSummary.analysisText` became optional for the same reason — a score-only
provider never generates one, so the PDF export's AI section now shows just the score + fixed
rationale sentence when that's all there is. The PDF's AI section heading and footer sentence,
previously hardcoded to "Apple Intelligence", are now provider-name-driven (`ReportExportView`) —
that bug predates this feature (it was already wrong for LM Studio etc.) but was fixed here since
leaving it wrong specifically for Jev would've been a correctness bug shipped on purpose.
