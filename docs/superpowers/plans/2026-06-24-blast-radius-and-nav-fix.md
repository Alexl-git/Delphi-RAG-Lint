# Nav fix + Symbol-Search removal + Blast Radius tab - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) tracking. This plan was authored autonomously while the user was away; design decisions are documented below and may be adjusted by the user.

**Goal:** (a) Fix result-navigation so clicking a result opens the .pas CODE (not the form designer); (b1) remove the legacy "Symbol Search" dock tab (the new "Search (no grep)" tab replaces it); (b2) replace the "Find Usages" dock tab with a **"Blast Radius"** tab showing clickable caller symbols + source links.

**Architecture:** All three are small, localized plugin changes. The nav fix is a one-function change to the shared `OpenSourceAt` (fixes the Search tab, Symbol Search, and hover popups at once). The tab changes are in `DockForm` (+ a label tweak in `UsagesForm`). No new units, no engine/CLI changes.

**Tech Stack:** Delphi 13, VCL, RAD Studio OTAPI/ToolsAPI. Built as the design-time BPL `dclDragLintWizard` (Win32).

## Global Constraints

- Source files strict 7-bit ASCII, CRLF. After any Edit (LF), normalize to CRLF.
- DocInsight `///` on new public surface (none expected here - these are edits to existing routines).
- Build the BPL via the **delphi-build** skill: `src\delphi-plugin\dclDragLintWizard.dproj`, Config=Debug, Platform=Win32. Confirm `BUILD_EXITCODE=0`, no `[dcc] Error`. The BPL must NOT be loaded in a running RAD Studio instance (link lock) - the user has closed the IDE for this autonomous run.
- Repo `C:\Projects\Delphi-RAG-lint`, branch `feat/blast-radius-and-nav-fix` (off main @ 3871544).
- Forms are not unit-testable (need the IDE); gate = clean BPL build + the manual TEST-CHECKLIST. Use drag-lint index queries (not grep) for any symbol lookups.

## Design decisions (authored autonomously - user may revise)

- **Blast Radius tab = repurpose the existing Find Usages embed.** `query usages --name <sym> --format json` already returns the clickable tree of Declarations / Reads / Writes / Calls / Type-uses / Events (each a file:line row that jumps to source) PLUS an Impact roll-up. Renaming that tab to "Blast Radius" + the nav fix (Task 1) delivers exactly "clickable symbols and source links" for the blast radius, reusing tested code at low risk.
- **Why NOT a full multi-level transitive tree now:** verified via CLI that `impact --qname --format json` returns ONLY per-depth COUNTS (`levels:[{depth,callers,units}]`), no locations; and `find-callers`/`usages` return caller call-site locations but NOT the enclosing caller symbol, so the plugin cannot cheaply recurse to build a deep clickable tree. A true multi-level tree needs an engine/CLI enhancement (emit the enclosing symbol per caller, or a new `blast-radius --tree` command). **Documented FOLLOW-UP, out of scope for this pass** - the user can greenlight it as its own brainstorm+spec.
- **Symbol Search:** remove only the dock TAB (`CreateEmbeddedSymbolSearch`); keep the `SymbolSearchForm` unit and its `ShowSymbolSearch` modal (still invoked by the Tools menu "Symbol Search" item) - do not delete the unit.

---

### Task 1: Navigation opens .pas code, not the form designer

**Files:**
- Modify: `src\delphi-plugin\DragLint.Plugin.HoverForm.pas` (`OpenSourceAt`, ~line 106-130)

**Root cause:** `OpenSourceAt` calls `ActSvc.OpenFile(AFile)` directly; for a FORM unit the IDE surfaces the designer/DFM, not the .pas. `UsagesForm.ShowSourceEditorFor` already solves this by forcing the `IOTASourceEditor`.

- [ ] **Step 1: Force the source editor in `OpenSourceAt`.** Before the goto-line logic, open the module and explicitly show its `IOTASourceEditor` (mirror `TDragLintUsagesForm.ShowSourceEditorFor` in `DragLint.Plugin.UsagesForm.pas` ~line 724-750). Replace the body so it: validates the rooted path (keep the existing guard); tries `IOTAModuleServices.OpenModule(AFile)` then iterates `Module.GetModuleFileEditor(i)`, and for the one that `Supports(Editor, IOTASourceEditor, Src)` calls `Src.Show` (this forces the CODE view, not the designer); FALLS BACK to `ActSvc.OpenFile(AFile)` only if no source editor was found; then proceeds to the existing `IOTAEditorServices.TopView` goto-line/Paint logic. Add `IOTAModuleServices`/`IOTAModule`/`IOTAEditor`/`IOTASourceEditor` locals. Keep `ToolsAPI` in uses (already there).

- [ ] **Step 2: Build the BPL** (delphi-build skill, Debug/Win32). Expected `BUILD_EXITCODE=0`, no `[dcc] Error`.
- [ ] **Step 3: Normalize CRLF** on HoverForm.pas, then **Commit**: `git add src/delphi-plugin/DragLint.Plugin.HoverForm.pas && git commit -m "fix(plugin): OpenSourceAt forces the .pas code editor, not the form designer"`

Manual verify (user, post-build): in any tab, click a result whose unit is a FORM (e.g. TfrmControlPlan2) -> the .pas CODE opens at the line, not the designer.

---

### Task 2: Tab restructure - remove Symbol Search, rename Find Usages -> Blast Radius

**Files:**
- Modify: `src\delphi-plugin\DragLint.Plugin.DockForm.pas`
- Modify: `src\delphi-plugin\DragLint.Plugin.UsagesForm.pas` (embed header label only)

Current DockForm tabs (after the Search-tab merge): `FTabStruct` 'Structure', `FTabUnifiedSearch` 'Search (no grep)', `FTabUsages` 'Find Usages', `FTabSearch` 'Symbol Search', (FTabGraph removed earlier). `HandleInitTimer` embeds: Structure, Search, Usages, SymbolSearch.

- [ ] **Step 1: Remove the Symbol Search tab.** In `DockForm.pas`: delete the `FTabSearch:= AddTab('Symbol Search');` line in the constructor and the `FTabSearch` field; delete the `try CreateEmbeddedSymbolSearch(...) except ... end;` block in `HandleInitTimer`. If `DragLint.Plugin.SymbolSearchForm` is now otherwise unused in DockForm's uses, the compiler will hint - leave the unit in the dpk/dproj (its `ShowSymbolSearch` is still used by the Tools menu). Do NOT delete the SymbolSearchForm unit.
- [ ] **Step 2: Rename Find Usages -> Blast Radius.** Change `FTabUsages:= AddTab('Find Usages');` to `AddTab('Blast Radius');` (optionally rename the field `FTabUsages` -> `FTabBlast` for clarity; if you do, update its 2-3 references). Keep the `CreateEmbeddedUsages(Self, <that tab>)` embed exactly as-is (it already shows the clickable caller tree + impact roll-up).
- [ ] **Step 3: Relabel the embed header.** In `UsagesForm.pas` `CreateEmbeddedUsages`, the top label/edit caption currently reads "Usages of:" / " Usages of: " - change the embed's visible label to "Blast radius of:" (the search box for the symbol). (The standalone `ShowFindUsages` window caption can stay; only the embedded dock label changes.) Use the index to find the exact label literal: `drag-lint query --text "Usages of:" --substring --db C:\Projects\.drag-lint\Delphi-RAG-lint.sqlite --json` (dogfood; don't grep).
- [ ] **Step 4: Build the BPL** (Debug/Win32). Expected clean.
- [ ] **Step 5: Normalize CRLF** on both files, then **Commit**: `git add src/delphi-plugin/DragLint.Plugin.DockForm.pas src/delphi-plugin/DragLint.Plugin.UsagesForm.pas && git commit -m "feat(plugin): replace Symbol Search + Find Usages tabs with a Blast Radius tab"`

Manual verify (user): panel shows tabs Structure | Search (no grep) | Blast Radius (no Symbol Search); Blast Radius lists clickable callers that open code.

---

### Task 3: Docs - checklist + changelog

**Files:**
- Modify: `docs\TEST-CHECKLIST.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1:** In `docs\TEST-CHECKLIST.md`, update the panel section: tabs are now Structure / Search (no grep) / Blast Radius (Symbol Search tab removed). Add checks: B1 clicking a FORM-unit result opens the .pas code (not designer); B2 Blast Radius lists clickable callers + impact roll-up; B3 no Symbol Search tab.
- [ ] **Step 2:** In `CHANGELOG.md`, under the IDE-plugin section, add: navigation now opens the .pas code for form units; the dockable panel's Symbol Search tab was folded into "Search (no grep)"; "Find Usages" became "Blast Radius" (clickable callers + impact).
- [ ] **Step 3: Commit**: `git add docs/TEST-CHECKLIST.md CHANGELOG.md && git commit -m "docs(plugin): Blast Radius tab + nav-fix checklist/changelog"`

---

## After all tasks
Final whole-branch review (opus) over the branch's merge-base..HEAD, then `finishing-a-development-branch` (the user will likely want to manually test in the IDE before merge, since the UI is user-verified). Known documented follow-up: a true multi-level transitive clickable Blast-Radius tree (needs engine/CLI support to emit enclosing-symbol-per-caller).
