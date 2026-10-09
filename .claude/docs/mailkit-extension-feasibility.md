# Apple Mail extension feasibility (MailKit)

Researched 2026-10-09 against current Apple Developer Documentation. Conclusion: we cannot ship
an in-Mail "Summary items below the header" view or an in-Mail "open in Mail Inspector" button
using public API. Don't re-propose this without re-reading this doc first.

## What MailKit actually offers

MailKit (macOS 12+) is the only public Mail extension framework. An extension declares one or
more capabilities in its `Info.plist` under `NSExtensionAttributes.MEExtensionCapabilities`:

- `MEContentBlocker` — Safari-style content-blocking rules (e.g. block remote image loads).
- `MEMessageActionHandler` — `decideAction(for:completionHandler:)` fires **automatically** as
  Mail downloads a message. It can flag/color/move-to-junk/archive. It is not user-invoked, has no
  UI, and isn't tied to "the message currently open in the reading pane."
- `MEComposeSessionHandler` — can show a custom view controller, but only inside the **compose**
  window (address validation, popovers, custom headers). Nothing in the reading pane.
- `MEMessageSecurityHandler` — encrypt/sign (`MEMessageEncoder`) and decrypt/verify
  (`MEMessageDecoder`) messages.

None of these expose a general "inject arbitrary UI below the header for any message" hook.

## The one banner hook that exists — and why it doesn't apply to us

`MEMessageSecurityHandler.decodedMessage(forMessageData:)` returns an `MEDecodedMessage`
containing `MEMessageSecurityInformation` (`isEncrypted`, `signers`, `signingError`,
`encryptionError`). When decoding needs to report a problem, the handler can attach an
`MEDecodedMessageBanner` (`title`, `primaryActionTitle`, `isDismissable`) and **Mail renders that
natively** as a full-width bar above the message body, with a working action button.

This is exactly how GPG Mail (gpgtools.org) shows its "activate your GPG Mail Support Plan"
nag/banner with an "Activate" button — confirmed from a screenshot of it running in current Mail.
It's a legitimate, sanctioned MailKit mechanism, not a private API or injected view.

It does not generalize to our use case:

- The documented contract for `decodedMessage(forMessageData:)` is to return `nil` when the
  message isn't encrypted/signed — in which case Mail decodes it normally and shows no banner.
  The banner is meant to report a genuine decode/signature problem, not to be a free-standing ad
  slot.
- To get a banner on *every* message (not just encrypted ones), we'd have to declare
  `MEMessageSecurityHandler` and claim a non-nil decode result for plain mail we don't actually
  encrypt or sign. That's declaring a capability that doesn't match what the extension actually
  does — likely an App Review problem, and it puts our analysis code in Mail's decode path for
  every message in every mailbox (a stability/perf liability for an unrelated feature).
- Mail Inspector's whole pitch is trustworthiness/authenticity analysis. Faking a
  security-handler role just to surface an "activate AI analysis" nag would undercut that.

## Conclusion / fallback

No inline summary view, no in-Mail action button — not available to us via public API.

Fallback path: an AppleScript dropped into `~/Library/Application Scripts/com.apple.mail/`
(shows up in Mail's own Script menu) that reads `tell application "Mail" to get selection`, grabs
the raw `source` of the selected message, writes it to a temp `.eml`, and hands it to Mail
Inspector's existing import path (`EmailImportCoordinator` / `FileOpenRequest`). The user then
binds a keyboard shortcut to that exact menu item via System Settings → Keyboard → Keyboard
Shortcuts → App Shortcuts → Mail. Everything except that last manual bind step can be automated
by Mail Inspector (e.g. a "Set up Mail integration" button in Preferences that installs the
script).

This is unlike the old "Mail Bundle" plugin mechanism (private API, requires disabling library
validation / SIP protections for Mail.app, breaks on macOS/Mail updates) — the Script menu +
AppleScript dictionary approach is fully supported, sandboxed-friendly, and doesn't require
weakening Mail's hardened runtime.
