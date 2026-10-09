# Mail Inspector build progress

Building "Mail Inspector", a sandboxed macOS SwiftUI app that inspects suspicious emails
(RFC 5322 parsing, SPF/DKIM/DMARC reporting, delivery-path reconstruction) without opening them
in Apple Mail. The original spec was given as a single large multi-phase brief (Phases 1-5); work
proceeded incrementally, validating each phase (build + tests) before moving to the next. Don't
try to redo multiple phases' worth of work in a single pass if more phased work is ever added here.

Progress as of 2026-10-09:
- Phase 1 (functional prototype: RFC 5322 header parser, address parser, RFC 2047 decoding,
  file-based `.eml` import via file picker/drop, raw headers view, sender identity view, 31
  passing Swift Testing unit tests) — **done**.
- Phase 2 (Apple Mail drag-and-drop via `NSFilePromiseReceiver`, `.emlx` unwrapping, Dock-icon
  drops via `NSApplicationDelegateAdaptor`, 34 tests total) — **done**, see
  `dock-icon-drop-fragility.md` for the two recurring bugs in this area.
- Phase 3 (Authentication-Results/DKIM-Signature parsing, trusted-authserv settings UI,
  SPF/DKIM/DMARC verdicts, DMARC domain alignment via a real downloaded Public Suffix List,
  52 tests total) — **done**.
- Phase 4 (Received-header delivery path reconstruction, IP scope classification,
  claimed-vs-verified hostname mismatch detection, trust-boundary marking reusing the Phase 3
  trusted-authserv list, SenderIdentityAnalyzer for Reply-To/Return-Path/display-name/IDN/mixed-
  script discrepancies, SecurityHeaderCatalog for ARC-*/X-Spam-*/Microsoft anti-spam headers,
  78 tests total) — **done**.
- Phase 5 (polish/accessibility/full fixture suite) — done, see below.

Committed through Phase 4 plus the post-Phase-4 real-inbox fixes in commit `0d400e5`
("Implement Phase 4 and real-inbox-driven fixes...").

**Phase 5:**
1. Added `license.txt` (MIT, copyright "(c) 2026 Nicholas K. Dionysopoulos") at the repo root,
   a `README.md` (project description + `## License` section), and a copyright/license docblock
   header on every Swift file in the project (both `Mail Inspector/` and `Mail InspectorTests/`),
   per explicit user request.
2. Added 3 tests to cover previously-untested edge cases: `malformedFoldingOrphanContinuation`
   (orphan fold-continuation line with no preceding header), `messageWithBinaryAttachment`,
   `messageWithMaliciousHTMLBody` (confirming header parsing ignores body content, including
   deliberately malicious HTML) — bringing the suite to 97 tests.
3. Accessibility pass: `DeliveryPathView`/`AuthenticationView` detail-row labels switched from
   fixed `frame(width:)` to `frame(minWidth:)` so they don't clip at large Dynamic Type sizes;
   `ObservationsSummaryView` rows got explicit VoiceOver severity labels ("Warning"/"Notable"/
   "Informational") plus `.accessibilityElement(children: .combine)`, since severity was
   previously conveyed only by icon shape/color.
4. **Split the single 959-line `Mail_InspectorTests.swift` into one file per `@Suite`** (18
   files, e.g. `EmailHeaderParserTests.swift`, `AddressParserTests.swift`, ... each starting with
   the standard license header followed by a doc-comment describing what functionality that suite
   tests, per explicit user request ("Docblocks at the head of each file should describe which
   part of the app's functionality we are testing"). The file-scope `private func makeTestMessage`
   (used by 8 of the 18 suites, 48 call sites) could not stay `private` once split across files —
   moved to a new `TestHelpers.swift` with internal (default) visibility.

**How to apply:** when adding new tests going forward, add them to (or create) the per-suite
file matching the type under test, not a single monolithic test file. If a new suite needs a
message-building helper shared with existing suites, put it in `TestHelpers.swift`, not file-scope
`private`.

**Post-Phase-4 additions, driven directly by the user reviewing a real inbox against the app:**
1. **Fixed a real `ReceivedHeaderParser` bug**: `parseFromClause` used
   `firstIndex(of: "(")`/`lastIndex(of: ")")` across the whole from-clause, which merged an
   unrelated second parenthetical (e.g. a `(using TLSv1.3 with cipher ... (256/256 bits))`
   TLS-info remark) into the reverse-DNS hostname, producing false "hostname mismatch" warnings
   on most hops of at least one real message (mailbox.org-relayed mail). Fixed with proper
   depth-matched parenthetical extraction (`firstMatchedParenthetical`) that only looks at the
   *first* `(...)` group. Also added prose-style TLS parsing (`using TLSv1.3 with cipher X`,
   Dovecot/mailbox.org style) alongside the existing `version=`/`cipher=` (Postfix/Exim style).
2. **`trustAllAuthenticationResultsByDefault`** (`InspectorSettings`, default **on**): when on,
   every `Authentication-Results` header is treated as trusted regardless of `authserv-id`,
   bypassing the explicit allowlist entirely. User's rationale: the spec-literal "trust nothing
   until told otherwise" posture doesn't match how people actually use this — the receiving
   server that handed you the message is, in practice, already being relied on.
2b. **`trustServerSpamHeaders`** (default **off**) + `SpamLikelihoodAnalyzer` +
   `SpamLikelihoodView`: an opt-in gauge (SwiftUI `Gauge`, `.accessoryCircular`) rescaling
   whatever a spam filter already reported (`X-Spam-Score`, `X-Spam-Status`'s `score=`, or
   Exchange's SCL) onto a 0-100% display. Explicitly documented as reflecting the filter's own
   number, not an independently computed probability — this bends the spec's "avoid a single
   score" guidance on purpose, at the user's explicit request, behind an off-by-default toggle.
3. **Live SPF recheck** (`SPFEvaluator` + `DNSResolver` + `SPFRecheckTargetResolver` +
   `ReceivedSPFParser`, triggered by a manual "Recheck SPF Now" button in `AuthenticationView`,
   SPF row only): the **second** network feature, and the only one that does real verification
   rather than parsing reported results. Uses `import dnssd`'s `DNSServiceQueryRecord` (bridged
   directly, no bridging header needed — confirmed importable) for TXT/A/AAAA/MX lookups, run on
   a background thread via `poll()` + `DNSServiceProcessResult`, wrapped as `async`. Full
   mechanism support: `ip4`/`ip6` (byte-level CIDR matching via `Network.IPv4Address`/
   `IPv6Address.rawValue`), `include` (recursive), `a`, `mx`, `all`, `redirect=`; bounded to
   RFC 7208's 10-DNS-lookup budget and 10 levels of include/redirect nesting. **Known limitation,
   deliberately accepted**: `mx` mechanism exchange hostnames that use DNS name compression can't
   be decoded from `DNSServiceQueryRecord`'s per-record rdata alone (compression pointers
   reference the full DNS message, which this lower-level API doesn't expose) — `decodeMXExchange`
   detects compression pointers and returns `nil` rather than mis-decoding, so those `mx`
   mechanisms just don't match rather than crashing or lying. **Empirically validated against real
   DNS** via `RunCodeSnippet` before writing a single test: `epafos.gr`'s real SPF record
   correctly passes/fails for known-good/known-bad IPs; `google.com` itself genuinely has no SPF
   record at its bare apex (confirmed by querying it directly, not a resolver bug) — `_spf.google.com`
   (which it `include`s from customer domains) tested clean.

This is a project-wide pattern worth repeating: for low-level C-interop (`dnssd`) or anything where
"does this actually talk to the real world correctly" can't be answered by reasoning alone, run it
for real via `RunCodeSnippet` before trusting it or writing tests against it.

**Round of real-inbox feedback, all resolved:**
1. Added Rspamd (`X-Rspamd-Score`, format "score / required / reject") and mailbox.org
   (`X-MBO-SPAM-Probability`, often blank) to both `SpamLikelihoodAnalyzer` and
   `SecurityHeaderCatalog`. Rspamd's score is rescaled *relative to its own required-score field*
   (which varies by deployment), not a hardcoded range — `score/required*50` lands the
   deployment's own spam threshold at 50%.
2. `DeliveryPathAnalyzer` no longer flags a *leading* run of private/reserved-IP hops as
   noteworthy — that's the normal shape of most SaaS senders (app server → internal mail-sender
   → internal aggregator → the SMTP server that actually faces the internet). Only a private IP
   that appears *after* the chain has already touched a public address gets flagged now (tracked
   via a `hasSeenPublicAddress` flag, oldest-to-newest). RFC 5737 documentation/test-net ranges
   (`203.0.113.x`, `198.51.100.x`) are themselves non-public per this app's own classifier — don't
   reuse them as "public" stand-ins in fixtures.
3. Dragging a `.eml` onto the sidebar/detail pane while messages already exist now works —
   added `.onDrop` directly to the `List` and the detail container (reusing the already-proven
   `NSItemProvider`-based extraction, not the window-level `MailDropReceiver`, which a `List`'s
   own AppKit drag handling was apparently shadowing).
4. Added message removal (context menu, swipe/`onDelete`, Delete key via `onDeleteCommand`) and
   a File ▸ Open… / ⌘O command (bridged via a tiny `FileOpenRequest` observable signal, since
   `.commands` runs outside any view and can't flip a view's own `@State` directly).
5. **Dock-drop double-window bug and Mail.app drag-to-window re-investigation** — see
   `dock-icon-drop-fragility.md`.

**Phase 3 architectural note — the app is no longer purely offline by default.** The user
explicitly asked (mid-Phase-3) for organizational-domain alignment to use the real downloaded
Public Suffix List (https://publicsuffix.org/list/public_suffix_list.dat, with a GitHub raw
mirror as fallback source) rather than a short hardcoded heuristic, specifically because they
receive a lot of mail from `gov.gr`/`gov.cy` government subdomains that a naive two-label guess
handles wrong. This required enabling `ENABLE_OUTGOING_NETWORK_CONNECTIONS` (the
`com.apple.security.network.client` entitlement) on the "Mail Inspector" target, which the
original spec's "works entirely offline" / "no network requests" language otherwise forbids.
Reconciled by making it a visible, user-toggleable Settings feature
(`InspectorSettings.isPublicSuffixListUpdateEnabled`, **default on** per the user's request),
documented in Settings UI copy and in `Analysis/PublicSuffixList.swift`'s doc comment, with a
small bundled fallback list (including `gov.gr`/`gov.cy` explicitly) so the app still works fully
offline with the toggle off or before the first successful download.

**How to apply:** if asked to add more network-touching features, follow this same pattern —
visible Settings toggle, explicit justification in both UI copy and code comments, graceful
offline fallback, and keep this doc's "network requests this app makes" framing accurate as new
ones are added (see also `on-device-mlx-llm.md`'s model-download feature, which follows the same
pattern: visible, user-initiated, with an offline-capable fallback of "just don't download it").

**Confirmed macOS/Mail.app limitation (Phase 2), found via hands-on user testing:** dragging a
message directly from Apple Mail's message list onto *any* third-party application window —
Mail Inspector's included — never fires `draggingEntered`, regardless of drag-destination
mechanism tried (a nested `NSView` via `NSViewRepresentable`, and a registered `NSWindow`
delegate, both failed identically). Diagnostic bisection ruled out a bug on our side: Finder →
Mail Inspector works; Mail.app → Finder works (produces a `.eml`); Mail.app → Mail Inspector's
**Dock icon** works (a completely different code path, `AppDelegate.application(_:open:)` +
`PendingImportQueue`). Conclusion: on this macOS version, Mail's drag source only completes
promise drags against Finder/Dock-owned destinations, not arbitrary third-party windows — a
platform limitation, not an app bug, documented in `Import/MailDropReceiver.swift` and reflected
in `DropZoneView`'s copy.

Re-investigated once more after the user found that dragging a Mail message into Notes/TextEdit/
Calendar/Reminders inserts a `message:<id>` URL (proving Mail's drag source vends *something*
generically droppable). Broadened `WindowDragDestination.acceptedTypes` to add `.URL`/`.string`
and re-tested with diagnostic logging: `draggingEntered` **still never fired**, even once — rules
out "wrong pasteboard type" definitively. Working theory, not provable from the outside: Mail's
drag source special-cases which destination apps it even considers valid (first-party bundle-ID
allowlist or private entitlement) rather than negotiating purely by declared type.

**How to apply:** don't re-attempt to fix direct Mail→window dragging without new evidence (e.g.
a macOS update, or discovering Mail actually vends a different pasteboard type in a future
version) — the dead ends above were real, hands-on-tested dead ends, not guesses. If asked to
revisit, the fastest path is the same one used here: add temporary `NSLog` diagnostics to
`draggingEntered`, have the user attempt the drag, then read `GetConsoleOutput`.

**Apple Intelligence (FoundationModels) feature** — an on-device legitimacy score (0-100
`@Generable` struct), a prefab prose analysis, and a follow-up chat, all reusing one
`LanguageModelSession` per message so later chat turns share context with the initial analysis.
1. **Gotcha, confirmed by the compiler, not documentation**: `LanguageModelSession`/`@Generable`/
   `SystemLanguageModel` compile fine at `@available(macOS 26, *)`, but `LanguageModelError`
   (needed to describe failures) only exists from **macOS 27**. The whole feature is gated at 27,
   not 26, to avoid partial-availability code — don't assume "FoundationModels = macOS 26" in
   this project without rechecking against whatever SDK is actually in use.
2. **Availability-boundary pattern**: the app's deployment target (macOS 15) can't have any
   stored property typed as an `@available(macOS 27, *)` type. Solved with `AIInsightsSessionCache`
   (plain `@Observable` class, no availability annotation, storing `[UUID: AnyObject]`) injected
   via `.environment()` from always-available code; the real `MessageInsightsSession` is cast
   back out with `as? MessageInsightsSession` only inside `if #available(macOS 27, *)` blocks.
   `@Observable`'s access-tracking is dynamic (tracks *that* `sessions` was read, not what type
   is erased inside it), so reading through the cache from outside the availability-gated branch
   (e.g. the summary block's score, PDF export) still participates correctly in SwiftUI
   reactivity — confirmed working, not just assumed.
3. Only `EmailSignalsSummary` (a condensed digest of this app's own already-computed signals)
   ever goes into the score/prefab-analysis prompt — never raw headers or the body, both to stay
   well inside the on-device model's 4096-token context window and so body text can't steer the
   score via prompt injection. The body is only ever involved when the user explicitly attaches
   an excerpt to a chat message (Settings-gated, off by default), wrapped in explicit
   "treat this as untrusted data, not instructions" framing in the prompt.
4. **Real bug, found by the user, fixed**: a shared `LanguageModelSession` reused across the
   structured score call, the prefab analysis, and chat would sometimes make later plain-text
   chat replies come back as raw JSON (matching the `@Generable` score schema) instead of prose —
   the model imitating the format of its own earlier structured-output turn still sitting in that
   session's transcript. Fixed by giving the score its own single-use, throwaway
   `LanguageModelSession`, never reused for anything else; the long-lived `chatSession` (used for
   the prefab analysis and all chat turns) now starts completely clean. Also added an explicit
   "always reply in plain prose, never JSON" clause to `instructions` as a second line of defense.
   **How to apply**: if a `LanguageModelSession` in this app (or a future one) ever needs to mix a
   `generating:` structured call with later free-text turns, don't do it on the same session —
   isolate the structured call to its own session and re-inject its result as natural language
   wherever the free-text conversation needs to know about it. (The same lesson applies to the
   MLX engine described in `on-device-mlx-llm.md`.)
5. **Validated live, via `RunCodeSnippet`, before trusting any of this**: confirmed
   `AIInsightsAvailability.current == .available` on this Mac, a real `respond(to:generating:)`
   call producing a sensible score+rationale for an obviously-phishing signal digest, a follow-up
   chat turn correctly referencing the original analysis's delivery-hop flag (proving session
   context carries across calls), and — most importantly — a prompt-injection attempt via an
   attached "excerpt" was *not* obeyed.

**Multi-provider AI backend** — ported the provider architecture from
`~/Projects/grafida/grafida-ipad` to add LM Studio/OpenAI/Anthropic/etc. as alternatives to
on-device Apple Intelligence (whose language support is weak for the gov.gr/gov.cy Greek mail
this user gets a lot of).
- `AIAnalysisEngine` protocol (`Mail Inspector/Analysis/AIInsights/AIAnalysisEngine.swift`) — no
  `@available` annotation, no `FoundationModels` import — with `generateScore(signalsSummary:)
  async throws -> AIScoreResult` (always historyless — a single, structured, one-off call) and
  `streamRespond(prompt:) -> AsyncThrowingStream<String, Error>` (each yielded value is the
  *cumulative* text so far, not a delta — matches `LanguageModelSession.streamResponse`'s own
  `Snapshot.content` behavior, confirmed via `RunCodeSnippet` before committing to that contract).
- `OnDeviceAIEngine` (`@available(macOS 27, *)`) wraps Apple's framework behind that protocol. The
  `@Generable` `MessageLegitimacyAssessment` type is `private` to that one file — leaving it
  public would have silently dragged the macOS 27 requirement back onto the whole class; the
  plain `AIScoreResult` (in `AIAnalysisEngine.swift`) is what the rest of the app uses.
- `MessageInsightsSession` holds `private let engine: any AIAnalysisEngine` and knows nothing
  about which backend it's talking to, including error descriptions (each engine throws an
  already-human-readable `AIEngineError`). Each engine owns its own conversation continuity
  internally.
- `AIWireDialectHandler.swift`: the shared protocol all three remote dialects conform to
  (`requestBody`/`parseNonStreamingContent`/`parseSSELine`). **Gotcha**: every requirement had to
  be explicitly marked `nonisolated` in the protocol itself — without it, this project's
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting makes a *protocol's* requirements implicitly
  MainActor-isolated, which then forces conforming witnesses to match that isolation even when
  the conforming type is declared `nonisolated enum`. Same risk applies to any future shared
  protocol in this project with static/non-async requirements.
- `AIScoreJSONParser.swift`: shared score-JSON extraction (markdown-fence stripping, clamping)
  used by every non-Apple-FoundationModels engine — this is the stand-in for Apple's native
  `@Generable` on every provider that can't do schema-constrained decoding, including the MLX
  engine (see `on-device-mlx-llm.md`).
- `AIProviderCatalog.swift`/`AIEngineFactory.swift`: catalogue of `AIProviderDefinition` rows +
  `AIWireDialect`/`AIProviderKind` enums, and the factory that resolves the active one into a real
  engine (`resolveActiveEngine`) or just checks readiness cheaply (`isActiveProviderReady`, used
  by the summary block's per-render pending-check so it doesn't construct a throwaway engine on
  every render).
- `AIKeychainStore.swift`: stateless `enum` with `set`/`get`/`delete(forProvider:)`,
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Settings never reads a key back into the
  UI — a blank field always means "keep existing."
- `AITransportPolicy.swift`: rejects plain `http://` to anything but a local address, reusing
  `IPAddressClassifier`. `.local`/`localhost`/loopback/private-use/link-local all pass; anything
  else requires HTTPS.
- Three wire dialects: `AIOpenAICompletionsWire.swift` (also used by every OpenAI-compatible
  hosted provider and LM Studio), `AIOpenAIResponsesWire.swift` (OpenAI's own Responses API),
  `AIAnthropicWire.swift` (Anthropic's Messages API, mandatory `anthropic-version` header handled
  as a dialect-specific special case regardless of the generic auth scheme).
- **Validated against real HTTP, not just fixtures**: a throwaway Python `http.server`-based mock
  OpenAI/Anthropic/OpenAI-Responses-compatible endpoint (SSE streaming, JSON score replies,
  `/models` listing, a wrong-API-key 401 case) driven via `RunCodeSnippet`, confirming real score
  generation, real streamed multi-turn chat, real model listing, and real auth-failure mapping —
  not just that the pure parsing functions handle fixtures correctly.
- 155/155 tests passing as of this writing.

Key architectural decisions made in Phase 1 (apply to later phases too):
- Project build settings use `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Xcode's new-project
  default), so every pure data/parsing type (models, parsers, import coordinator) must be marked
  `nonisolated` explicitly or it cannot be called from the background `Task.detached` used to
  keep parsing off the main thread. This includes private helper types in the same file — isolation
  is not inherited from the enclosing file's other declarations.
- Header parsing works on raw bytes (`[UInt8]`), never `String(data:encoding:.utf8)` directly,
  because that would throw/return nil on malformed input. Decoding always tries UTF-8 first, then
  falls back to ISO Latin-1 (which can represent any byte 0-255) — reuse this pattern for any
  future byte-level parsing.
- `AddressParser` is a hand-rolled recursive-descent scanner (no third-party dependency) covering
  RFC 5322 mailbox/address-list/group syntax, comments, quoted-strings, and RFC 2047 decoding of
  display names. Reused by `EmailMessage`'s From/To/Cc/Reply-To/Sender accessors.
- Module name is `Mail_Inspector` (spaces become underscores) — tests use
  `@testable import Mail_Inspector`.
- Test target: "Mail InspectorTests", Swift Testing (not XCTest), embedded in the "Mail Inspector"
  app target.
- Screenshot/visual verification of the running app is not available in this environment
  (`screencapture` fails with "could not create image from display" — no screen-recording
  permission for the harness). Verification relies on: build success, `RunAllTests`, and
  `RunProject` + `GetConsoleOutput` showing no crash.
