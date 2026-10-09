# Agent notes

- Before proposing or implementing anything that touches Apple Mail's own UI (a Mail app
  extension, an in-Mail banner/button, injecting views into the reading pane), read
  `.claude/docs/mailkit-extension-feasibility.md` first — this has already been researched and
  most of what you'd think to try is not possible with public API.
- When a change adds a user-facing feature (a new report section, Settings toggle, export option,
  etc.) or changes the behavior of one already described in `README.md`, update `README.md` in
  the same change: add a new bullet for a new feature, or edit the existing one if behavior
  changed (default value, requirements, wording). Don't leave it for a later pass.
