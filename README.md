# Mail Inspector

Inspect the legitimacy of the emails you receive in Apple Mail on macOS

## Overview

Mail Inspector is a native macOS app for inspecting potentially malicious email without opening
it in Apple Mail. Drop an `.eml` or `.emlx` file, open one or more from Finder, or drag a message
onto the Dock icon, and Mail Inspector parses the raw RFC 5322 source and builds a report with the
sections below.

Mail Inspector never renders HTML, never executes scripts or attachments, and never follows links.
Message content is never logged or persisted beyond what you explicitly import.

## Report sections

- **Noteworthy Observations** (off by default) — an optional summary at the top of the report,
  gathering every flagged finding from the sections below into one list. Severity labels and
  plain descriptions only, deliberately not a single score, so you form your own judgment rather
  than anchoring on one number.
- **Sender identity** — the actual `From` address and display name, with discrepancies (forged
  display names, Reply-To/Return-Path mismatches, IDN/Punycode domains, mixed-script display
  names) surfaced as observations, not accusations. A Reply-To mismatch you've reviewed can be
  marked safe for that sender from right there in the report, so it stops being flagged. Can
  optionally show the sender domain's published BIMI brand logo, but only once DMARC is a trusted
  pass (and, optionally, only above/below a spam-score threshold you set).
- **Authentication** — SPF, DKIM, and DMARC results parsed from `Authentication-Results` and
  `DKIM-Signature` headers (including full DKIM signature detail: algorithm, canonicalization,
  signed headers, selector, signing identity, timestamps), with an explicit trust model: a result
  is only shown as trusted when it comes from an `authserv-id` you've configured (or, by default,
  treated as trusted outright — configurable in Settings). DMARC domain-alignment (strict/relaxed)
  is shown for both SPF and DKIM. An optional, manually-triggered SPF recheck can re-run the check
  against the record as it exists *right now* via a real DNS lookup — one of only two network
  requests this app ever makes.
- **Spam Likelihood** (off by default) — a gauge built from a spam-scoring header your mail
  provider's filter already added (`X-Spam-Score`, Exchange's Spam Confidence Level, Rspamd,
  mailbox.org, etc.), rescaled for display. Never an independent assessment — the report always
  says so.
- **Delivery path** — a reconstructed, chronological timeline from every `Received` header, with
  IP-scope classification (private/loopback/reserved), reverse-DNS hostname mismatches, TLS
  version/cipher per hop, and chronological/timing anomalies flagged — all without treating
  anything outside your own trusted infrastructure as proof of wrongdoing. A hostname mismatch you've
  reviewed can likewise be marked safe for that specific claimed/verified pair.
- **AI Message Analysis** (off by default) — a 0-100 legitimacy gauge, a short prose analysis, and
  a follow-up chat, generated from the signals already shown elsewhere in the report (SPF/DKIM/
  DMARC, delivery path, spam score) — never the raw headers or message body, unless you explicitly
  opt in to attaching a text excerpt to a specific chat question. Runs fully on-device via Apple
  Intelligence (macOS 27+, eligible hardware, zero configuration), fully on-device via a model you
  download once and run locally through MLX (Apple Silicon Macs only — a small, broadly-compatible
  model and a larger one gated at 16GB of memory), or against a remote provider you configure: LM
  Studio or another local OpenAI-compatible server, and a catalogue of hosted providers (OpenAI,
  Anthropic, Google, Mistral, Cohere, DeepSeek, Groq, MiniMax, OpenRouter, Perplexity, Scaleway,
  GitHub Models), plus a fully custom OpenAI-compatible endpoint. Two further options, **Jev** and
  **System One (Jev) compatible**, use TypeSafe.ai's System One API instead — a fast decision-maker
  that returns only a 0-100% legitimacy score for each message, with no further insight and no
  chat against the message's headers or content. Jev talks to TypeSafe.ai's own hosted service;
  System One compatible points at any live or locally-hosted service speaking the same API (e.g.
  Laya (local), Clef (local, online)) — the built-in prompt is tuned for TypeSafe.ai's Jev and may
  not give satisfactory results with other services. API keys are stored in the Keychain, never in
  plain settings. It's a model's opinion, not a verdict — it can be confidently wrong. The system
  prompt sent to whichever chat-capable provider is active (and, for Jev/System One compatible,
  the question it asks instead) is itself editable in Settings, with a "Reset Prompt" button to
  restore the tested default if an edit makes things worse.
- **Additional Filtering Headers** — known chain-of-custody and anti-spam headers this app doesn't
  otherwise parse structurally (ARC-*, Received-SPF, X-Spam-*, Microsoft 365/Exchange anti-spam
  headers, Rspamd, mailbox.org), shown as-is with a plain-language explanation of what each means.
  Never reimplements any filter's scoring logic.
- **Raw headers** — a searchable, monospaced, read-only view of the complete original headers,
  with one-click copy of a single header or the entire header block.

## Report export

A message's report can be exported or shared as a paginated PDF (⌘E to save, ⇧⌘E to share via the
system share sheet — Mail, Messages, AirDrop, Save to Files, …), at a page size you choose (US
Letter, US Legal, A4, or A5) in Settings. If the AI analysis has already been generated for that
message, its score and analysis are included in the export.

## Settings

- Trust configuration: which `authserv-id`s to trust for Authentication-Results (or trust all by
  default), plus the Reply-To-domain and delivery-hop-hostname exceptions you've marked safe from
  the report itself.
- Import limit: maximum accepted message size, checked before and after reading untrusted input.
- Domain alignment data: whether to keep a weekly-refreshed copy of the public suffix list (used
  to tell a subdomain apart from an unrelated domain for DMARC alignment) up to date — the only
  other network request this app ever makes, besides the manual SPF recheck above. Off by default
  falls back to a small bundled list.
- Noteworthy Observations, Spam Filtering, Brand Images (BIMI), and AI Message Analysis: each
  toggled independently, all off by default except where noted above.
- Report export page size.

> [!IMPORTANT]
> You cannot drag a mail directly onto the app window. This is a limitation of macOS and Mail.app.
> When dragging an email onto an application, Mail.app only includes a message ID to create a deep
> link which opens the mail in Mail.app. It does not send the mail content itself, let alone the
> mail headers we actually need to analyse. When you are dragging an email onto an app's Dock icon,
> though, it sends the entire email message – and that's why that drag and drop operation works.
> Yes, it is annoying and inconsistent. That's how Apple designed it. I can only work with what
> Apple gives me to work with, folks.

## Requirements

- macOS (latest SDK), Swift 6, SwiftUI + AppKit.
- Third-party dependencies: `mlx-swift-lm` and `swift-transformers`, used only by AI Message
  Analysis's on-device MLX option.
- AI Message Analysis's Apple Intelligence option requires macOS 27+ with Apple Intelligence
  enabled on eligible hardware; its on-device MLX option requires an Apple Silicon Mac with
  enough free memory for the model you pick. Every other feature, including the rest of AI
  Message Analysis (a remote provider), works without either.

## Building

Open `mailinspector.xcodeproj` in Xcode and build the `Mail Inspector` scheme.

## License

Mail Inspector is released under the MIT License. See [license.txt](license.txt) for the full
text.

Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd.
