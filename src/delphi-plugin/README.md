# drag-lint Delphi IDE Plugin

A design-time package for RAD Studio 13 Florence (37.0) that surfaces
drag-lint's capabilities inside the editor: hover, go-to-definition,
completion, signature help, Find Usages, structure, rename, live
diagnostics, YADF formatting, the dockable panel, and the graph viewer.

> Version: this file tracks the package constant `PLUGIN_VERSION` (currently
> `v0.40.5-alpha` in `DragLint.Plugin.Editor.pas`). Rebuild the BPL to pick up
> newer code; the plugin is versioned independently of the `drag-lint.exe` CLI.

## Build

```
cd src/delphi-plugin
cmd.exe /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && msbuild dclDragLintWizard.dproj /p:Platform=Win64 /p:Config=Debug /v:minimal"
```

Output: the design-time BPL (`dclDragLintWizard.bpl`) under `<repo>\build\`.
Close any running IDE instance first if the BPL is locked.

## Install

1. Copy `drag-lint.exe` (Win64) to a folder on PATH, or set its path in the
   plugin Settings. The plugin spawns it for indexing, LSP, hover, and compile.
2. In RAD Studio 13: **Component -> Install Packages... -> Add**.
3. Browse to the built `dclDragLintWizard.bpl`.
4. Click OK. The IDE confirms `drag-lint` is loaded.
5. Restart RAD Studio.

## Verify

After restart, a top-level **`drag-lint`** menu appears on the main menu bar
(it falls back to a submenu under **Tools** only if the main bar is
unavailable). It exposes the plugin's actions directly and via grouped
submenus:

- **drag-lint** (dockable panel) and **drag-lint Graph** (viewer launcher)
- Hover at Cursor, Go to Definition, Show Completion, Show Signature Help
- Grouped submenus such as **Uses & Dependencies**, **Inspect Symbol**,
  **Code Quality**, **Generate & Export**, and **Index & Maintenance**
- Rename Symbol, Format with YADF, Settings

Place the cursor on an identifier and pick **Hover at Cursor**; a popup shows
the symbol's information from drag-lint. **Run Diagnostics** populates the
Messages pane with lint findings.

## Troubleshooting

- "drag-lint LSP failed to start" -- `drag-lint.exe` not found on PATH or in
  Settings.
- "Hover request timed out" -- `drag-lint.exe` crashed; check stderr.
- Empty hover content -- no doc row for that symbol; rebuild the index with a
  current drag-lint.

## Files

| File | Purpose |
|------|---------|
| `DragLint.Plugin.Wizard.pas` | IOTAWizard implementation + Register |
| `DragLint.Plugin.LspClient.pas` | TDragLintLspClient (subprocess + JSON-RPC) |
| `DragLint.Plugin.Editor.pas` | Menu registration, action handlers, diagnostics routing |
| `dclDragLintWizard.dpk` | Pascal-level package descriptor |
| `dclDragLintWizard.dproj` | MSBuild project file |
