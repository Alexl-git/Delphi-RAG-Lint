# drag-lint - full IDE feature test plan

End-to-end pass of everything experienced in or through RAD Studio: the plugin's
menu, the live editor integrations, navigation/refactor/diagnostics, the
Tools->Options page, and the graph viewer's IDE handoff. Each step has an
**action** and the **expected** result. Tick it; note anything off and grab
**Tools -> drag-lint -> Open Plugin Log** if something misbehaves.

Detailed per-item menu behaviour lives in `TEST-PLAN-IDE-TOOLS-MENU.md`; this
doc is the wider sweep and references it for section A.

> **Targets v0.45.0-alpha** (index-manifest era; engine is **Win64**, the 32-bit
> IDE drives it out-of-process). This is the IDE/plugin + graph-viewer pass. For
> driving drag-lint from an **AI agent over CLI or MCP** (no IDE), test against
> [`docs/AI-USAGE.md`](AI-USAGE.md) instead — that path has its own instructions.

---

## 0. Setup (do once)

- [ ] **0.1 Indexes current (DONE).** All indexes were freshly rebuilt by the
      v0.45 engine: ORM3 (`C:\Projects\DB\ORM3\drag-lint.sqlite`), SQL,
      per-platform libraries (`C:\Projects\.drag-lint\library-Win32.sqlite` /
      `library-Win64.sqlite` / ...), all-projects (`C:\Projects\drag-lint-all.sqlite`),
      and the working-set DBs in `C:\Projects\.drag-lint\`. Nothing to rebuild.
- [ ] **0.2 Install the 32-bit BPL.** Component -> Install Packages -> Add ->
      browse to
      **`C:\Projects\Delphi-RAG-lint\third_party\dll-win32\dclDragLintWizard.bpl`**
      (its build location). IDE confirms `drag-lint` loaded. The engine is now
      **Win64-only**; the current Win64 `drag-lint.exe` + `drag-lint.json`
      (manifest) + `drag_lint_graph.exe` are placed in BOTH `dll-win32` and
      `dll-win64`, so the BPL spawns the right engine from beside itself either
      way. (The 32-bit IDE drives the Win64 engine out-of-process -- no shim.)
- [ ] **0.3 Engine + manifest beside the BPL (auto).** The plugin finds
      `drag-lint.exe` (Win64, v0.45) and `drag-lint.json` next to the installed
      BPL automatically -- no PATH/Settings needed. The Graph window launches
      `drag_lint_graph.exe` from the same folder.
- [ ] **0.4** Open an ORM3 unit with real code and a project that compiles.
- [ ] **0.5 Test Connection** (Tools -> drag-lint -> Test Connection...) reports
      drag-lint reachable + a version. Do this first; if it fails, fix before
      continuing.

---

## A. Tools -> drag-lint menu (17 entries)

Run the full per-item checklist in **`TEST-PLAN-IDE-TOOLS-MENU.md`** (Hover,
Completion, Signature Help, Run Diagnostics, Rename, Compile & Diagnose, Import
Build Log, Format with YADF, Show Structure, Run AST Checks, Find Usages, Symbol
Search, Dockable Panel, Settings, Lint Buffer, Test Connection, Open Plugin Log).

- [ ] **A.smoke** The submenu lists all 17 entries in order and none raises an
      error when clicked on a valid unit.

---

## B. Live editor integration (no menu click)

- [ ] **B1 Dwell hover.** Rest the mouse on an identifier ~1.6s (don't click) ->
      a short LSP summary popup (kind + signature). Moving away dismisses it; it
      does not double up with the menu's richer Hover.
- [ ] **B2 Gutter markers.** Open a unit with a known issue (or introduce a
      syntax error) -> a gutter glyph appears on the offending line.
- [ ] **B3 Wavy underline.** The same problem shows a coloured wavy underline
      under the offending token.
- [ ] **B4 Error-Insight replacement.** Diagnostics surface inline (markers +
      messages) without a full compile, via the AST/LSP path.
- [ ] **B5 Keyboard shortcuts.** The plugin's registered keystrokes fire the
      common actions (hover/completion/etc.) without opening the menu. Confirm
      at least one bound key works.
- [ ] **B6 Marker clears.** Fix the issue -> the marker/underline clears on the
      next diagnostics pass (save or Run Diagnostics).

---

## C. Navigation & search

- [ ] **C1 Show Structure** (Tools -> drag-lint -> Show Structure) opens the
      drag-lint Structure dockable for the active unit; **Refresh** updates it;
      selecting an element moves the editor caret.
- [ ] **C1b Structure right-click nav (v0.43).** Right-click a method row ->
      **Go to Declaration** lands on the interface line; **Go to Implementation
      (body)** lands on the `TClass.Method` body; **Find Usages** opens the
      usages view for that symbol.
- [ ] **C2 Find Usages.** Caret on a symbol -> Find Usages... -> a list of every
      reference; double-click jumps to the site.
- [ ] **C3 Symbol Search.** Symbol Search... -> type a partial name -> results
      filter live (debounced); choosing one opens it at the definition.
- [ ] **C4 Dockable Panel.** "drag-lint Panel (dockable)" opens a tabbed panel
      (Structure / Find Usages / Symbol Search / Graph) you can dock like
      GExperts.
- [ ] **C5 Graph window (v0.43).** View -> Tool Windows -> **drag-lint Graph**
      opens a dedicated dockable window with the graph **embedded in-place**;
      dock it beside Structure (both visible). Single-click a leaf node ->
      jumps to its source in the IDE. Closing the window terminates the viewer.
- [ ] **C6 Hover Parameters (v0.43).** Hover a proc/method -> the popup shows a
      **Parameters** block (one `name : type` per line, `const`/`var`/`out`
      preserved) + **Returns**, even with no doc-comment.

---

## D. Refactor & format

- [ ] **D1 Rename Symbol.** Caret on a **throwaway** local/symbol -> Rename
      Symbol... -> new name -> definition + references update. Undo or use a
      scratch unit so nothing unwanted is committed.
- [ ] **D2 Format with YADF.** On a unit under version control (or a saved
      copy), Format with YADF -> the unit reformats; revert after confirming.

---

## E. Diagnostics

- [ ] **E1 Run AST Checks** (no compiler) -> tree-sitter ERROR/MISSING spots
      reported with (line,col); clean unit -> none.
- [ ] **E2 Lint Buffer (Unsaved).** Type an error but DON'T save -> Lint Buffer
      reflects the in-memory edit (not the on-disk file).
- [ ] **E3 Compile && Diagnose** -> project compiles; compiler errors map to
      lines (Error-Insight style).
- [ ] **E4 Import Build Log...** -> pick a saved compiler log -> its diagnostics
      show against the right files/lines.

---

## F. Tools -> Options -> drag-lint

- [ ] **F1** A native **drag-lint** page exists under Tools -> Options.
- [ ] **F2** Changing a setting (e.g. the exe path or workspace mode) and
      clicking OK persists; reopening Options shows the saved value.

---

## G. Graph viewer <-> IDE

The viewer is now its own published tool:
[Delphi-RAG-Lint-Graph](https://github.com/Alexl-git/Delphi-RAG-Lint-Graph) -
download the **v0.1.0-alpha** release (win32 **or** win64; each bundles its
`sqlite3.dll`) or build it. Launch it (its own process) against the refreshed
indexes:

    drag_lint_graph.exe --db C:\Projects\DB\ORM3\drag-lint.sqlite ^
                        --db C:\Projects\Delphi-RAG-lint\third_party\dll-win32\drag-lint-library.sqlite

- [ ] **G1 Open-source jump.** Click a member/record in the graph -> the IDE
      comes forward and opens the .pas at the **exact line/col**; the viewer
      status bar reads `Opened in IDE: ...:line:col`.
- [ ] **G2 Lands right.** The caret is on the actual declaration, not the file
      top and not a different file (the recent OpenFile-guard fix).
- [ ] **G3 Structure panel.** Left dock lists units -> Interface / Implementation
      -> Types / Consts / Vars / Routines, plus **Initialization / Finalization**
      and **Uses (interface/impl)** + **Used by** (from the fresh init/final +
      unit_uses data). Drill to members.
- [ ] **G4 Search box.** Type `ABC` -> substring matches (XXXABCYYY). Toggle
      "Partial match" off -> exact only. Scoped: `MSCTYPES.Plan`,  `TPlanType.`.
- [ ] **G5 Tree <-> graph selection.** Select a tree item -> it is selected and
      centered (readable zoom) in the graph. Select a node in the graph -> the
      matching tree row highlights. Both directions.
- [ ] **G6 Right-click parity.** Right-click a tree item -> Open Source / Go to
      Interface / Where Used / Show in Graph -- same actions as the graph's own
      right-click menu, and they visibly act.
- [ ] **G7 Resizable panel.** Drag the splitter between the list and graph -> the
      list area resizes (live).
- [ ] **G8 Graph usability.** Left-drag pans; mouse-back / Backspace goes up;
      no "mystery hubs"; collapsed nodes + hubs are labelled; UML/record/enum
      boxes scroll (scrollbar) and resize (corner grip); no flicker on scroll.

---

## G-Flow. Code Flow View (NEW)

A new **Flow mode** in the graph viewer: from a chosen symbol it builds a
**static call tree** (what that routine calls, transitively, in source order)
and draws it as a **vertical flowchart** of boxes annotated from DocInsight
doc-comments. Undocumented symbols still show name + parameters. The pure
engine/DB/view-model layers are covered by **58 headless tests**; the items
below are the **GUI surface those tests can't exercise**.

> **Build note:** Flow mode lives on branch **`feat/graph-viewer-real`** and is
> NOT in the v0.1.0-alpha release. Build the viewer from that branch
> (`build\build_viewer.bat`) and launch as in section G, OR test it embedded in
> the IDE graph window (C5) after installing a plugin BPL built from the same
> branch. Run against ORM3 **+** library DBs so cross-store callees resolve.

**Entry points (three ways in):**

- [ ] **GF1 Tree -> Trace flow.** Right-click a method/proc/function in the
      left **structure tree** -> **Trace flow from here** -> the right pane swaps
      from the graph to a flowchart: the chosen symbol is the top box, its
      callees are boxes below it joined by connector lines. A **Back to Graph**
      and a **Brief/Expanded** button appear; the **Flow** toolbar button hides.
- [ ] **GF2 Graph node -> Trace flow.** Right-click a **graph node** -> **Trace
      flow from here** -> same flowchart, rooted at that node.
- [ ] **GF3 Toolbar Flow button.** Select a graph node, then click the **Flow**
      toolbar button -> enters flow from the selected node. With **nothing**
      selected, clicking Flow shows the status hint
      `Select a graph node first, then click Flow.` (no crash, no blank pane).
- [ ] **GF4 Back to Graph.** Click **Back to Graph** -> the graph returns
      exactly as it was; the Flow/Brief buttons toggle back. Round-trip a few
      times -> only one of graph/flow is ever visible (no overlap, no flicker).

**Rendering & graceful degradation:**

- [ ] **GF5 Documented box.** Trace from a method that HAS a doc-comment -> its
      box shows the **summary** line under the signature.
- [ ] **GF6 Undocumented still useful.** A callee with NO doc-comment still shows
      its **name + parameters** (from the signature) plus a `[no doc]` marker --
      a box is **never blank**. (This is the core promise: useful even on
      undocumented code.)
- [ ] **GF7 Brief vs Expanded.** Click the detail toggle: **Brief** = signature
      + one-line summary on every box; **Expanded** = adds **parameter
      descriptions, Returns, Raises, Remarks, See-also** on documented boxes.
      The button caption reflects the mode (`Brief` / `Expanded`).
- [ ] **GF8 Per-box override.** In Brief mode, click a single box's **`+`** ->
      just that box expands (others stay brief). In Expanded mode, **`-`**
      collapses one box. The override survives a Brief<->Expanded toggle of the
      others.
- [ ] **GF9 Source order.** Sibling callees appear **in the order they are
      called** in the parent's body (top-to-bottom = first-to-last call site),
      not alphabetical. A method called several times in one body appears
      **once** (at its first call site).

**Bounds & exploration:**

- [ ] **GF10 Recursion.** Trace a recursive routine (calls itself directly or
      via a cycle) -> the repeat shows a **`(recursion)`** marker and does NOT
      expand forever.
- [ ] **GF11 External/unresolved leaf.** A call to an RTL/library/3rd-party
      symbol not in the loaded DB (or an unresolved call) shows as a terminal
      **`[external]`** box with no children (not expandable).
- [ ] **GF12 Truncation + expand.** Trace something wide/deep -> a node with
      many or deep callees shows a **`... N more`** line. **Click `... N more`**
      -> that node expands in place to reveal the omitted callees (count drops /
      children appear). Confirm it works on the **root** box too.
- [ ] **GF13 No outgoing calls.** Trace a leaf routine that calls nothing -> the
      root box shows **`(no outgoing calls)`**.
- [ ] **GF14 Scrolling.** A tall flow scrolls **vertically**; a deeply nested
      flow (indent ~6 levels) scrolls **horizontally** with the rightmost boxes
      fully reachable (not clipped).

**Cross-cutting:**

- [ ] **GF15 Flow -> tree sync.** Click a flow box -> the matching row
      **highlights in the structure tree** (so you can cross-reference / then
      Back-to-Graph with context).
- [ ] **GF16 Completeness vs display cap.** Trace a symbol in a **huge** store
      (e.g. the 1.57M-symbol library) -> the flow still shows its real callees
      even though the graph itself is node-capped at 20k (Flow queries the index
      directly, so it is not limited by the visible graph slice).
- [ ] **GF17 Cross-DB callee.** Trace a symbol whose callee lives in another
      store (ORM3 routine calling a **library** symbol, both DBs loaded) -> the
      callee box resolves and is labelled, not dropped.
- [ ] **GF18 Teardown safety.** **Close the viewer while in Flow mode** (don't
      Back-to-Graph first) -> it closes cleanly, no AV / no FastMM "freed block"
      dialog. Repeat embedded in the IDE (close the dockable Graph window while
      a flow is showing).

---

## H. Cross-DB resolution (refreshed library)

- [ ] **H1** In the viewer (with both ORM3 + library DBs), click a node that
      references a library type (e.g. something using `TObject` / `TList` /
      `IInterface`) -> it resolves into the **library** store (cross-DB jump),
      proving the refreshed 1.57M-symbol library DB is wired in.
- [ ] **H2** Library `initialization`/`finalization` now exist (3,388) -> a
      library unit's structure shows them (was absent before the refresh).

---

## I. Lifecycle (do last)

- [ ] **I1 Uninstall.** Install Packages -> uncheck `dclDragLintWizard` -> the
      IDE does NOT crash; the `drag-lint` submenu, markers, and dockables go away
      cleanly.
- [ ] **I2 Reinstall.** Re-add the package -> submenu + features return and work.

---

## J. Semantic + uses cleanup (CLI, v0.43)

Run from a prompt (PowerShell, **not** Git-Bash — it mangles `C:\` paths).
DB = `C:\Projects\DB\ORM3\drag-lint.sqlite`.

- [ ] **J1 check-unit (saved).** `drag-lint check-unit <unit.pas> --project
      <dproj> --platform win64 --db <DB> --format text` -> compiles the unit;
      a clean unit reports `0 error(s)`.
- [ ] **J2 check-unit (unsaved / shadow).** Copy the unit to a temp dir, delete
      a needed entry from its `uses`, and run with `--shadow <tempdir>
      --resolve-uses` -> reports `E2003 Undeclared identifier ... -- add unit X
      to the uses clause`, without touching the real file.
- [ ] **J3 cycles --edges.** `drag-lint cycles --db <DB> --edges` -> lists
      circular groups with `A uses B [section]` edges, move-to-implementation
      candidates, and any `[LAYERING: COMMON -> CLIENT]` flags.
- [ ] **J3b cycles --causes / --plan.** `--causes` pinpoints the symbols in each
      interface edge (with use + declaration line). `--plan` emits a markdown
      refactoring playbook (extract-contract vs invert-dependency, numbered
      steps, verify command) -- readable + followable; flags index-gap edges
      honestly.
- [ ] **J4 uses-audit.** `drag-lint uses-audit <unit.pas> --db <DB>` -> proposes
      interface→implementation moves + unused candidates (or "nothing").
- [ ] **J5 uses-fix dry-run.** `drag-lint uses-fix <unit.pas> --project <dproj>
      --db <DB>` -> shows the proposed uses-clause diff; writes nothing.
- [ ] **J6 uses-fix apply.** Add `--apply` -> the move is applied, a `.bak` is
      created, and an independent `check-unit` of the modified file still reports
      `0 error(s)`.
- [ ] **J7 sweep report.** `drag-lint uses-fix --project <dproj> --db <DB>`
      (no `<unit>`) -> a project-wide report of proposed moves/unused with totals.
- [ ] **J8 re-index is a no-op.** Re-run `drag-lint index C:\Projects\DB\ORM3
      --db <DB>` twice -> the second run reports `skipped N up-to-date` (no
      duplicate rows; the v0.43 canonical-path fix).

---

## K. Index Manifest + Settings + Platform (v0.45)

Config used: `third_party\dll-win64\drag-lint.json` (beside the Win64 engine).
Run CLI steps from a PowerShell prompt at `C:\Projects\Delphi-RAG-lint`.

- [ ] **K1 Edit config.** Open `third_party\dll-win64\drag-lint.json`; change
      `maxJobs` to `4` and save. Confirm the file is valid JSON (no parse error
      on next step).
- [ ] **K2 Dry-run plan.** `drag-lint index --all --dry-run --config
      third_party\dll-win64\drag-lint.json` -> prints a resolved plan with all
      nine sections; Library expands to one entry per registered platform
      (at minimum `library-Win32.sqlite` and `library-Win64.sqlite`); AllProjects
      shows a non-empty `dedupExcludeRoots`; exits 0.
- [ ] **K3 Dry-run JSON.** Add `--json` to the above -> output is valid JSON
      with a top-level `"sections"` array; section names match the config.
- [ ] **K4 Loader closure.** In the dry-run JSON, the Loader section has
      `"mode": "closure"` (resolved from the `.dproj` path, not `folderTree`).
- [ ] **K5 resolve-dbs Win32.** `drag-lint resolve-dbs --platform Win32 --config
      third_party\dll-win64\drag-lint.json` -> lists ORM3 + SQL + Loader +
      working-set DBs + `library-Win32.sqlite`; does NOT list `library-Win64.sqlite`.
- [ ] **K6 resolve-dbs Win64.** Same with `--platform Win64` -> lists
      `library-Win64.sqlite` instead; does NOT list `library-Win32.sqlite`.
- [ ] **K7 resolve-dbs --json.** `--json` variant -> output starts with `[`;
      each entry is a plain DB path string.
- [ ] **K8 Full index (non-dry, long).** `drag-lint index --all --jobs 4
      --config third_party\dll-win64\drag-lint.json` builds every section DB and
      ends with `parallel build: N/N sections OK` (verified 21/21). Library +
      AllProjects are long-running but DO complete; expect a handful of
      `SKIP ... exceeds parse limit` lines for multi-MB generated files. Use
      `--only ORM3,SQL` for a quick build-path smoke if time-constrained.
- [ ] **K9 Win32 BPL in 32-bit IDE.** Component -> Install Packages -> install
      `third_party\dll-win32\dclDragLintWizard.bpl` (the v0.45 Debug build).
      IDE confirms `drag-lint` loaded. Tools -> drag-lint submenu appears.
- [ ] **K10 Manifest-driven hover (no --db).** Open an ORM3 unit. Tools ->
      drag-lint -> Hover -> result shown (no "no DB" error). The plugin found
      the manifest and selected the ORM3 DB automatically.
- [ ] **K11 Manifest-driven Find Usages (no --db).** Caret on a symbol -> Find
      Usages -> usages list populated; no "specify --db" error.
- [ ] **K12 Platform swap library DB.** Switch the active project's target
      platform Win32 -> Win64 (Project Manager toolbar). Run Hover again ->
      confirm the library DB used switches from `library-Win32.sqlite` to
      `library-Win64.sqlite` (check plugin log for DB-selection trace).
      (This may require a later plugin task if the notifier is not wired yet --
      note the actual behaviour.)
- [ ] **K13 Graph viewer with manifest.** Launch `drag_lint_graph.exe` with no
      `--db` flag (or from the IDE dockable window, section C5) -> it shells
      out to `drag-lint resolve-dbs` and loads the manifest DB set; graph
      populates without a "no database" error.
- [ ] **K14 File-size guard.** `drag-lint index C:\Projects\DelphiBigNumbers\Tests\BigIntegers
      --db %TEMP%\bn.sqlite` -> exits 0 and prints `SKIP ... exceeds parse limit`
      for the multi-MB `*.inc` data files (default 2048 KB). Override with
      `--max-file-kb 5000` (indexes them; slower) or `--max-file-kb 0` (no limit;
      may crash on pathological generated files). Setting key: `maxParseFileKB`.
- [ ] **K15 Ignore files (.gitignore/.hgignore).** Index a tree that has a
      `.hgignore`/`.gitignore` with `--use-ignore` (ORM3 has an `.hgignore`) ->
      completes promptly (no hang), and ignored paths (e.g. `*BACKUP*`, `- Copy`,
      `OLD/`) are absent from the DB. Mercurial `.hgignore` regexp-default lines
      (before a `syntax: glob` line) are skipped; glob lines apply.

---

## How to report back
Per failing step: the number, what you saw, the unit/symbol involved, and any
text from **Open Plugin Log** or the Messages pane. That pins each issue fast.
