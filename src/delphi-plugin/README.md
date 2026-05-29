# drag-lint Delphi IDE Plugin (v0.21.0-alpha)

A design-time package for RAD Studio 13 Florence (37.0) that surfaces drag-lint's
LSP capabilities inside the editor: hover, completion, signature help, and
diagnostics.

## Build

```
cd src/delphi-plugin
cmd.exe /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && msbuild dclDragLintWizard.dproj /p:Platform=Win64 /p:Config=Debug /v:minimal"
```

Output: `<repo>\build\v021\dclDragLintWizard.bpl`.

## Install

1. Copy `drag-lint.exe` to a folder on PATH (or note its absolute path; the
   v0.21 wizard expects `drag-lint.exe` on PATH).
2. In RAD Studio 13: **Component → Install Packages... → Add**.
3. Browse to `<repo>\build\v021\dclDragLintWizard.bpl`.
4. Click OK. The IDE confirms `drag-lint` is loaded.
5. Restart RAD Studio.

## Verify

1. After restart, open any Delphi project.
2. Open a .pas file.
3. **Tools menu** should show a `drag-lint` submenu with four entries:
   - Hover at Cursor
   - Show Completion
   - Show Signature Help
   - Run Diagnostics
4. Place cursor on an identifier; click `Tools → drag-lint → Hover at Cursor`.
   A dialog should pop up with the symbol's information from drag-lint.
5. Click `Tools → drag-lint → Run Diagnostics`. The Messages pane should
   populate with any lint findings.

## Limitations (deferred to v0.22)

- No custom popup forms — results show in ShowMessage dialogs for now.
- No keystroke bindings — invocation is via menu only.
- No settings UI — drag-lint.exe is expected on PATH.
- No incremental editor updates — diagnostics run on Tools menu click only.
- No index auto-build — the plugin assumes you've run `drag-lint index` on
  the project's source folder already and that a `.drag-lint.sqlite` lives
  somewhere accessible.

## Troubleshooting

- "drag-lint LSP failed to start" — drag-lint.exe not found on PATH.
- "Hover request timed out" — drag-lint.exe crashed; check stderr.
- Empty hover content — no symbol_docs row for that symbol; ensure the index
  was built with v0.16+.

## Files

| File | Purpose |
|------|---------|
| `DragLint.Plugin.Wizard.pas` | IOTAWizard implementation + Register |
| `DragLint.Plugin.LspClient.pas` | TDragLintLspClient (subprocess + JSON-RPC) |
| `DragLint.Plugin.Editor.pas` | Tools menu handlers + diagnostics routing |
| `dclDragLintWizard.dpk` | Pascal-level package descriptor |
| `dclDragLintWizard.dproj` | MSBuild project file |
