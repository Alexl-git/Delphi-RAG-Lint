# drag-lint - full IDE feature test plan

End-to-end pass of everything experienced in or through RAD Studio: the plugin's
menu, the live editor integrations, navigation/refactor/diagnostics, the
Tools->Options page, and the graph viewer's IDE handoff. Each step has an
**action** and the **expected** result. Tick it; note anything off and grab
**Tools -> drag-lint -> Open Plugin Log** if something misbehaves.

Detailed per-item menu behaviour lives in `TEST-PLAN-IDE-TOOLS-MENU.md`; this
doc is the wider sweep and references it for section A.

---

## 0. Setup (do once)

- [ ] **0.1 Indexes current.** All four scan DBs are freshly built (with
      initialization/finalization): ORM3, SQL, all-projects, library. See
      `SCAN-DATABASES.md` for paths.
- [ ] **0.2 Rebuild + install the plugin BPL** to pick up the latest fixes
      (open-source GotoLine guard, v0.41 scanner): Component -> Install Packages
      -> uncheck `dclDragLintWizard` -> rebuild `dclDragLintWizard.dproj` ->
      re-add it. IDE confirms `drag-lint` loaded.
- [ ] **0.3 drag-lint.exe reachable** (PATH, beside the BPL, or set in
      Tools -> drag-lint -> Settings).
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
- [ ] **C2 Find Usages.** Caret on a symbol -> Find Usages... -> a list of every
      reference; double-click jumps to the site.
- [ ] **C3 Symbol Search.** Symbol Search... -> type a partial name -> results
      filter live (debounced); choosing one opens it at the definition.
- [ ] **C4 Dockable Panel.** "Dockable Panel (test)" opens a panel you can dock
      at the bottom/side like GExperts (docking plumbing check).

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

Launch the viewer (its own process) against the refreshed indexes:

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

## How to report back
Per failing step: the number, what you saw, the unit/symbol involved, and any
text from **Open Plugin Log** or the Messages pane. That pins each issue fast.
