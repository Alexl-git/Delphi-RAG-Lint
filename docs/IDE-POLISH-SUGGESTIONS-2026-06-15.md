# drag-lint IDE-polish punch-list - status + suggestions (2026-06-15)

Autonomous follow-up to the real-32-bit-IDE test session. Branch `feat/index-manifest`,
engine at **0.46.0-alpha** (NOT pushed). This doc says what I fixed, how to pick it up,
and - for the items that need live-IDE iteration - the root cause + the concrete approach
so the next debug pass is fast.

---

## A. FIXED + DEPLOYED - pick up with an IDE RESTART ONLY (no BPL reinstall)

These are all in the **engine** (`drag-lint.exe`), already redeployed to BOTH
`third_party\dll-win32\drag-lint.exe` and `dll-win64\drag-lint.exe` (same Win64 exe).
The plugin spawns the engine from beside the BPL, so just **restart the IDE**.

1. **Duplicate symbols / phantom "2 overloads" / mystery "line 309" - ROOT CAUSE FIXED.**
   `BuildPlanItem` opened the section DB and APPENDED, so a section built twice
   (ORM3 was: scoped reindex during dev, then the full `index --all`) doubled every
   symbol. New `RecreateSectionDb` deletes the DB + its `-wal/-shm/-journal` sidecars
   before each build = a clean rebuild every time. Regression test `selftest recreate`
   (build a one-file section twice, assert symbol count stable) - PASS (build1=4, build2=4).
   - **Re-indexed clean:** ORM3 (760 files / 43,608 syms), SQL, Loader, TableTools,
     DragLint, DragLintGraph, OCRPDF. Verified `btnCopyOperation` is now field x1 +
     component x1 (was x2 + x2).

2. **Hover content cleaned up** (`DRagLint.LSP.Server.pas`, `HandleHover`):
   - Dropped the mislabeled `_Resolved type: <qname>_` line (it printed the qualified
     NAME, not a type; the indented decl line below already shows `name: Type` like the IDE).
   - New `DedupAndPreferSource`: de-dups candidates by (qname, file, line) AND, when a
     source declaration is present, drops the generated DFM component - so a published
     field shows once with its real type instead of a phantom "2 overloads (field + DFM)".
   - Trimmed the gratuitous blank lines.
   - Verified end-to-end with a real LSP `textDocument/hover` at `btnCopyOperation`:
     ```
     **btnCopyOperation** `field`

     - `Blueprint4.TfrmBlueprint4.btnCopyOperation` - line 240
         var btnCopyOperation: TdxBarSubItem
     ```
   - Note: the `**`/backtick markdown still shows literally in the popup until you
     **reinstall the BPL** (item B1 strips it). With engine-only (restart) you already
     get NO phantom overloads, NO mystery line, real type, far less whitespace.

---

## B. FIXED in the BPL - pick up with a BPL REINSTALL (then restart)

Both BPLs rebuilt (`/t:Rebuild`) and deployed; **install the Win32 one** from
`third_party\dll-win32\dclDragLintWizard.bpl` (the 32-bit IDE). Graph-frame DFM +
hover-form classes verified linked.

1. **Hover popup renders clean + body is single-click navigable**
   (`DragLint.Plugin.HoverForm.pas`):
   - New `CleanHoverMarkdown` strips code-span backticks and `**` bold, unwraps
     whole-line `_..._` italics (without touching underscores inside identifiers like
     `MS_FOLDER`), and collapses runs of blank lines. The TMemo has no markdown engine,
     so this is what removes the literal `**`/backtick noise + the empty space.
   - `HandleMemoClick` now parses the cleaned `"- <qname> - line N"` row shape
     (no backtick gate) so plain single-click still jumps to source.

2. **Library DB resolution hardened** (`DragLint.Plugin.DbResolver.GetLibraryDbPath`):
   prefers `library-Win32.sqlite` / `library-Win64.sqlite` beside the BPL (the v0.45
   per-platform names), falling back to the legacy merged `drag-lint-library.sqlite`
   (still present + complete). No user-visible bug today - the legacy file works - but
   forward-compatible if you deploy the fresh per-platform DBs beside the BPL.

3. **Hover popup follows the IDE light/dark theme** (NEW request)
   (`DragLint.Plugin.HoverForm.ApplyIdeTheme`): guarded
   `IOTAIDEThemingServices.ApplyTheme(Self)` in the constructor (RegisterFormClass once).
   Wrapped in try/except so a missing service / older IDE just leaves the default light
   colours. **Please eyeball it in dark mode** - if child controls (memo/callers grid)
   don't recolour, the fix is `ApplyThemeToComponent` per child instead of `ApplyTheme`
   on the form. The dock + graph + other forms are NOT yet themed (see C7).

---

## C. NEEDS LIVE-IDE ITERATION - root cause + recommended approach (not yet coded)

I did not blind-code these: they need OTA behaviour you can only see in the running IDE,
or they are real features that deserve a test. Each has the diagnosis + the concrete plan.

1. **Graph window blank ("how to make it start?")**
   The dock launches `drag_lint_graph.exe --parent-hwnd <h> --db ...` and embeds the
   viewer's main window as a WS_CHILD (`DragLint.Plugin.GraphWindow.pas`). The viewer
   DOES draw a graph on `FormShow -> RunLoad` when `--db` is present
   (`Delphi-RAG-Lint-Graph\src\viewer\MainForm.pas`). Three likely causes, in order:
   - **(a) No `--db` reached the viewer.** `ResolveDbArgs` -> `ResolveActiveIndexDbs`
     returns empty when invoked with no active editor file (menu focus on Project Manager).
     **Test:** run `drag_lint_graph.exe --db "C:\Projects\DB\ORM3\drag-lint.sqlite"`
     standalone - if it shows a graph, the data path is fine and this is the cause.
     **Fix:** in `ResolveDbArgs`, fall back to the active project group's DB when the
     editor-derived list is empty; and show the resolver diagnostic in `FStatus` when no DB.
   - **(b) Child sized 0x0.** `HandlePollTimer` calls `SizeViewer` (= `MoveWindow` to
     `ClientWidth/Height`) the moment it finds the child; if the dock hasn't laid out yet
     those are 0 -> blank, and no later resize fires. **Fix:** in `SizeViewer`, skip while
     `ClientWidth<=0`, and also call `SizeViewer` from the frame's first paint.
   - **(c) `OnShow` never fires for the embedded WS_CHILD form** -> `RunLoad` never runs.
     **Fix:** in the viewer, also post `WM_LOADGRAPH` from the constructor (deferred) when
     `FParentHwnd<>0`, guarded by `FLoaded`, so the load doesn't depend on OnShow.
   Recommended: do (a)+(b) first (cheapest, no viewer rebuild for (a) is impossible -
     ResolveDbArgs is plugin-side; (b)+(c) need a viewer rebuild).

2. **Diagnostics right-click "Copy message" / "Copy all messages"**
   There is no diagnostics LIST today - findings are painted as squiggles
   (`EditViewNotifier`) fed by `DiagnosticCache`. So there's nothing to right-click yet.
   **Approach:** add a `TListView` (vsReport: Sev / Line / Rule / Message) to the dock
   panel (`DragLint.Plugin.DockForm`), populate from `DiagnosticCache` on each publish,
   and give it a `TPopupMenu` with "Copy message" (selected row) + "Copy all messages"
   (whole list, `file(line): SEV CODE: message` per line) -> `Clipboard.AsText`. Wire the
   cache's update to refresh the list. ~80 lines, but needs the dock open to verify layout.

3. **H2164 (unused local var) shown x3 to match the IDE - it's a missing rule, engine-side**
   Our diagnostics = (lint AST rules) + (semantic = `check-unit` compiler). The compiler
   path can't reproduce the IDE's clean H2164: an isolated-unit shadow compile emits
   missing-unit errors (no full project context), not the tidy unused-var hints. And there
   is **no AST unused-local-var rule** - that's why you see one lint warning, not three H2164.
   **Approach (real feature, deserves tests):** add `CheckUnusedLocals` to
   `DRagLint.Diagnostics.AstChecks` using tree-sitter-delphi13: for each routine with a
   block, collect locals from its `var` section(s), count identifier references in the body
   (excluding the decl), emit one `hint`/`H2164`-style finding per zero-reference local.
   Watch for: nested routines, `with`, out/var params, loop vars. Gate behind a setting.
   This is the right fix but should be TDD'd against a fixture unit - not a blind add.

4. **Gutter glyphs too small (match the IDE's larger icons)**
   `EditViewNotifier` draws the marker in `BeforeDrawLine`/gutter paint. The IDE's gutter
   glyph cell is ~16-18 px; we're drawing smaller. **Approach:** draw the squiggle/marker
   icon at the gutter row height (query `IOTAEditView` line height) and center it; or load a
   16x16 themed glyph. Needs the editor open to size-match visually.

5. **No diagnostic marks on the editor scrollbar**
   The IDE paints per-finding ticks on the scrollbar track. OTA has no first-class API for
   this; the IDE itself uses an internal margin painter. **Approach (harder):** the
   practical route is a custom overlay - subclass/owner-draw is not exposed. Realistic
   option: skip true scrollbar ticks, OR draw a thin "overview strip" control docked to the
   right of the edit view fed from `DiagnosticCache` (one pixel-row per finding mapped to
   file length). Document as lower priority / nice-to-have.

6. **Hover latency (slower than the IDE's instant hover)**
   The dwell tracker (`HoverTracker`) does an LSP round-trip per dwell. The shared LSP
   client is reused (no per-hover process spawn), so the cost is the request + the server's
   query. **Approach:** (i) cache the last hover result keyed by (file, line, col-token) so
   re-dwelling the same identifier is instant; (ii) lower the dwell debounce only after the
   first cached hit; (iii) confirm the LSP client isn't re-opening the DB per request
   (open once, keep the store resident). Measure first with `DRAGLINT_DEBUG` timing.

7. **Auto-refresh of the inline-info panel on caret/file change**
   The dock's info panel only fills on the Refresh button. **Approach:** subscribe to the
   editor view-change / caret-change notifier (you already have `EditViewNotifier`) and
   call the panel's refresh (debounced ~250 ms) so it follows the cursor. Also theme the
   dock here (C ties into B3).

---

## Quick install recap
1. **Engine-only wins (no reinstall):** just restart the IDE - the spawned
   `dll-win32\drag-lint.exe` is now 0.46 with the recreate fix + clean hover + clean ORM3 DB.
2. **Plugin wins:** IDE -> Components/Packages -> remove the old `dclDragLintWizard.bpl` ->
   install `C:\Projects\Delphi-RAG-lint\third_party\dll-win32\dclDragLintWizard.bpl` ->
   restart. You get the clean+clickable hover, themed popup, hardened DB resolution.
