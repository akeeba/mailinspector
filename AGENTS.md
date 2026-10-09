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
  `enable_thinking` gotcha, package-dependency setup).
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
