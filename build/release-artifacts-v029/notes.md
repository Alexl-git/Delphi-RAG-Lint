## v0.29.0-alpha -- 2026-05-29

### Added

- **In-editor visual diagnostics** -- LSP `publishDiagnostics` notifications now
  paint directly into the RAD Studio editor via `IOTAEditViewNotifier`:
  - **Gutter dot** (6x6 filled circle) on every diagnostic line, colored by
    max severity on that line.
  - **Wavy underline** (2-pixel sawtooth) over the diagnostic column range,
    one per diagnostic item.
  - **Ctrl+Alt+I** -- displays a `THintWindow` popup with all diagnostic
    messages for the current cursor line.
- **Registry-aware colors** (`DragLint.Plugin.RegistryColors`) -- reads
  `HKCU\Software\Embarcadero\BDS\37.0\Editor\Highlight\` keys (`Syntax Error`,
  `Warning`, `Hint`, `Information`) so markers honor the user's custom IDE color
  theme.
- **Per-severity toggles** -- 5 new settings (`EnableInlineMarkers`,
  `ShowErrorsInline`, `ShowWarningsInline`, `ShowHintsInline`, `ShowInfoInline`)
  exposed in the Settings dialog. Defaults: markers on, Info off.
- **T47** -- smoke test: registry color reader returns non-zero defaults.
- **T48** -- smoke test: diagnostic cache stores and retrieves by file + line
  with case-insensitive path matching.

### Notes

- Mouse-hover tooltip deferred to v0.30; Ctrl+Alt+I is the v0.29 substitute.
- Theme-switch detection is not live; colors are read once at plugin load.
  Restart the IDE after changing editor colors.