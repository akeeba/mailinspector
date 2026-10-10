# Agent notes

- Before proposing or implementing anything that touches Apple Mail's own UI (a Mail app
  extension, an in-Mail banner/button, injecting views into the reading pane), read
  `.claude/docs/mailkit-extension-feasibility.md` first — this has already been researched and
  most of what you'd think to try is not possible with public API.
- Before working on the AI-analysis feature (`Analysis/AIInsights/`), read
  `.claude/docs/build-progress.md` for the architectural decisions already made (the
  `AIAnalysisEngine` protocol, per-backend history isolation, the structured-score-vs-chat
  session split) and, if the on-device MLX provider specifically is involved, also read
  `.claude/docs/on-device-mlx-llm.md` (model choices, JSON-schema test findings, the
  `enable_thinking` gotcha, package-dependency setup); if Jev/System One compatible specifically
  is involved, also read `.claude/docs/system-one-jev.md` (wire shape, why it's a separate
  `AIProviderKind`/engine, the `context_length` assumption, and the chat-capability gating that
  change needed everywhere else).
- Before touching Dock-icon file drops or `AppDelegate.application(_:open:)`, read
  `.claude/docs/dock-icon-drop-fragility.md` — this exact mechanism has broken twice already for
  two different reasons.
- Project knowledge (architectural decisions, test findings, recurring bugs and their root
  causes) belongs in a committed doc under `.claude/docs/`, referenced from this file — not in
  any assistant's own local/machine-specific memory, which the next session (or a different
  machine) won't have access to.
- When a change adds a user-facing feature (a new report section, Settings toggle, export option,
  etc.) or changes the behavior of one already described in `README.md`, update `README.md` in
  the same change: add a new bullet for a new feature, or edit the existing one if behavior
  changed (default value, requirements, wording). Don't leave it for a later pass.
- Any new or modified user-facing string (in a String Catalog, Info.plist, or elsewhere) must be
  translated into all of the app's supported languages in the same change: English (UK, `en-GB`),
  Greek (`el`), German (`de`), Dutch (`nl`), French (`fr`), Spanish (`es`), Portuguese — Portugal
  (`pt-PT`), and Turkish (`tr`). Don't leave strings untranslated for a later pass.
