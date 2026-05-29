## v0.22.0-alpha -- 2026-05-29

### Added (IDE polish)

- **Auto-index on project open** (`DragLint.Plugin.ProjectNotifier`). The
  plugin hooks `IOTAIDENotifier.FileNotification`; when a `.dproj` opens,
  it spawns `drag-lint.exe index <projdir> --db <projdir>\.drag-lint.sqlite`
  asynchronously (CreateProcessW with DETACHED_PROCESS) and posts an
  "indexing project..." title message to the IDE Messages pane. Honors the
  AutoIndex toggle (default ON) from settings.

- **Settings persistence + Tools menu dialog** (`DragLint.Plugin.Settings`
  + `DragLint.Plugin.SettingsForm`). Registry-backed config at
  `HKCU\Software\drag-lint\DelphiPlugin` with seven fields: ExePath,
  DbPathTemplate (use `<projdir>` for project dir), AutoIndex, EnableHover,
  EnableCompletion, EnableSignature, EnableDiagnostics. Modal VCL settings
  dialog built programmatically (no .dfm). New menu entry "Settings..."
  under Tools > drag-lint.

- **Keystroke bindings** (`DragLint.Plugin.Keyboard`) via
  `IOTAKeyboardServices.AddKeyboardBinding`:
  - `Ctrl+Alt+H` → Hover at Cursor
  - `Ctrl+Alt+C` → Show Completion
  - `Ctrl+Alt+S` → Show Signature Help
  - `Ctrl+Alt+D` → Run Diagnostics
  Each handler checks the corresponding Enable* setting before invoking.

- **Custom hover popup form** (`DragLint.Plugin.HoverForm`). Borderless
  `fsStayOnTop` VCL form replaces `ShowMessage` for hover only.
  TMemo content (Consolas 9pt), auto-sized up to 600x400, positioned just
  below the cursor. Auto-closes on ESC, click-outside (deactivation), or
  after 30s.

### Notes

- Completion + signatureHelp still use `ShowMessage` in v0.22; their custom
  popups move to v0.23.
- Incremental `didChange` editor updates and pre-D13 IDE versions remain
  deferred.