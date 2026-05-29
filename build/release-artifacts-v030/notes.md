## v0.30.0-alpha -- 2026-05-29

### Added (IDE integration)

- **Custom Structure form** (`DragLint.Plugin.StructureForm`) -- Tools >
  drag-lint > Show Structure opens a non-modal, stay-on-top TForm with
  a TTreeView populated with two roots:
  - "Diagnostics (N)" -- pulled from the v0.29 diagnostic cache;
    severity prefix + message; double-click jumps editor to line.
  - "Code Elements (M)" -- pulled from a new `TDragLintStructureCache`
    that shells out to `drag-lint surface` per file. Cached per file
    path.
  Refresh button re-pulls both. Form is a separate window rather than
  injecting into the IDE's native Structure pane (sibling-tab
  registration requires custom-window hosting that is too fragile
  across BDS versions; v0.31+ may revisit).

- **Native Tools > Options page** (`DragLint.Plugin.Options` +
  `DragLint.Plugin.OptionsFrame`) -- implements `INTAAddInOptions` so
  drag-lint appears under Tools > Options as a proper IDE-native panel.
  Frame hosts all v0.22-v0.29 settings (drag-lint.exe path, project DB
  template, AutoIndex, AutoReindexOnSave, EnableHover/Completion/
  SignatureHelp/Diagnostics, EnableInlineMarkers + 4 per-severity
  toggles). Save happens on OK click; Cancel discards changes.
  The Tools > drag-lint > Settings... menu shortcut remains and now
  shows the same form in a modal wrapper for users who prefer the menu
  flow.

### Notes

- Structure form is a standalone TForm rather than docked into the
  IDE's Structure pane. Provides the same data with less integration
  risk.
- Options frame and modal SettingsForm now share the same field set;
  v0.31 may unify them into a single TFrame consumed by both contexts.
