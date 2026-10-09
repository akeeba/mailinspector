# Mail Inspector

Inspect the legitimacy of the emails you receive in Apple Mail on macOS

## Overview

Mail Inspector is a native macOS app for inspecting potentially malicious email without opening
it in Apple Mail. Drop an `.eml` file, open it from Finder, or drag a message onto the Dock icon,
and Mail Inspector parses the raw RFC 5322 source and shows you:

- **Sender identity** — the actual `From` address and display name, with discrepancies
  (forged display names, Reply-To/Return-Path mismatches, IDN/Punycode domains, mixed-script
  display names) surfaced as observations, not accusations.
- **Authentication** — SPF, DKIM, and DMARC results parsed from `Authentication-Results` and
  `DKIM-Signature` headers, with an explicit trust model: a result is only shown as trusted when
  it comes from an `authserv-id` you've configured (or, by default, treated as trusted outright —
  configurable in Settings). An optional, manually-triggered SPF recheck can re-run the check
  against the record as it exists *right now* via a real DNS lookup — the only other network
  request this app makes besides a weekly Public Suffix List refresh used for domain-alignment
  comparisons.
- **Delivery path** — a reconstructed, chronological timeline from every `Received` header, with
  IP-scope classification (private/loopback/reserved), reverse-DNS hostname mismatches, and
  chronological/timing anomalies flagged — all without treating anything outside your own trusted
  infrastructure as proof of wrongdoing.
- **Raw headers** — a searchable, monospaced, read-only view of the complete original headers.

> [!IMPORTANT]
> You cannot drag a mail directly onto the app window. This is a limitation of macOS and Mail.app.
> When dragging an email onto an application, Mail.app only includes a message ID to create a deep
> link which opens the mail in Mail.app. It does not send the mail content itself, let alone the
> mail headers we actually need to analyse. When you are dragging an email onto an app'sDock icon,
> though, it sends the entire email message – and that's why that drag and drop operation works.
> Yes, it is annoying and inconsistent. That's how Apple designed it. I can only work with what
> Apple gives me to work with, folks.

Mail Inspector never renders HTML, never executes scripts or attachments, and never follows links.
Message content is never logged or persisted beyond what you explicitly import.

## Requirements

- macOS (latest SDK), Swift 6, SwiftUI + AppKit.
- No third-party dependencies.

## Building

Open `mailinspector.xcodeproj` in Xcode and build the `Mail Inspector` scheme.

## License

Mail Inspector is released under the MIT License. See [license.txt](license.txt) for the full
text.

Copyright (c) 2026 Nicholas K. Dionysopoulos.
