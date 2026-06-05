# drag-lint IDE plugin - Tools menu test plan

Walk every entry under **Tools -> drag-lint** in RAD Studio, plus the related
IDE surfaces (Options page, dwell hover, graph open-source). Each step has an
**action** and the **expected** result. Tick the box; note anything off.

---

## 0. Setup

- [ ] **0.1** The plugin BPL is installed: Component -> Install Packages shows
      `dclDragLintWizard` (checked). On load, the IDE confirms `drag-lint`.

      > Heads-up: to get the latest fixes (esp. the open-source "only GotoLine on
      > successful OpenFile" guard and the v0.41 scanner), rebuild + reinstall the
      > BPL: uncheck it in Install Packages, rebuild `dclDragLintWizard.dproj`,
      > re-add it.

- [ ] **0.2** `drag-lint.exe` is reachable: either on PATH, beside the BPL, or
      set in Tools -> drag-lint -> Settings. (Test Connection, step 16, verifies.)
- [ ] **0.3** An index exists for the project's sources, e.g.
      `C:\Projects\DB\ORM3\drag-lint.sqlite` (the plugin/LSP uses it for
      hover/usages/search).
- [ ] **0.4** Open a real unit with code (e.g. an ORM3 unit) and a project that
      builds, so the compiler-based items have something to chew on.
- [ ] **0.5** **Tools -> drag-lint** submenu is present and lists the 17 entries
      below in order.

---

## 1. Hover at Cursor
- [ ] Put the caret on an identifier (a type/method/field) -> menu item.
- [ ] **Expected:** a hover popup with the symbol's kind + signature + doc
      summary, and (richer than dwell) its callers/3-section info.
- [ ] Press Esc or move away -> popup dismisses, no leftover artefact.

## 2. Show Completion
- [ ] Caret after a partial identifier or a `.` -> menu item.
- [ ] **Expected:** a completion list relevant to the context; picking one
      inserts it.

## 3. Show Signature Help
- [ ] Caret inside a call's parentheses (e.g. after `Foo(`) -> menu item.
- [ ] **Expected:** a borderless signature popup showing the routine's
      parameters (active param highlighted if supported).

## 4. Run Diagnostics (didSave)
- [ ] Menu item on the active unit.
- [ ] **Expected:** LSP diagnostics run; findings appear in the Messages pane
      (or as markers). A clean unit yields none.

## 5. Rename Symbol...
- [ ] Caret on a symbol you can safely rename -> menu item.
- [ ] **Expected:** a rename prompt; confirming updates the definition and its
      references. **Verify on a throwaway symbol** (or undo after) so you don't
      commit an unwanted rename.

## 6. Compile && Diagnose
- [ ] Menu item.
- [ ] **Expected:** the project/unit compiles and compiler errors/warnings are
      surfaced (Error-Insight-style) mapped to lines.

## 7. Import Build Log...
- [ ] Menu item -> pick a saved MSBuild/compiler log file.
- [ ] **Expected:** diagnostics parsed from the log are shown against the
      relevant lines/files.

## 8. Format with YADF
- [ ] Open a unit -> menu item.
- [ ] **Expected:** the unit is reformatted by YADF. **Use a unit under version
      control / save a copy first** so you can revert.

## 9. Show Structure
- [ ] Menu item.
- [ ] **Expected:** the drag-lint **Structure** dockable opens listing the code
      elements of the active unit; Refresh updates it; selecting an element
      navigates the editor.

## 10. Run AST Checks
- [ ] Menu item (no compiler needed).
- [ ] **Expected:** tree-sitter AST/syntax checks run; any ERROR/MISSING spots
      are reported with (line,col). Clean file -> none.

## 11. Find Usages...
- [ ] Caret on a symbol -> menu item.
- [ ] **Expected:** a usages list/form with every reference; double-click jumps
      to that site in the editor.

## 12. Symbol Search...
- [ ] Menu item.
- [ ] **Expected:** a modal search dialog with a debounced edit; typing filters
      symbols from the index; choosing one opens it.

## 13. Dockable Panel (test)
- [ ] Menu item.
- [ ] **Expected:** a placeholder dockable panel opens that you can dock/park
      like GExperts (proves the docking plumbing; content is a placeholder).

## 14. Settings...
- [ ] Menu item.
- [ ] **Expected:** a settings dialog: `drag-lint.exe` path (Browse...),
      workspace-mode checkbox. OK persists; Cancel discards.

## 15. Lint Buffer (Unsaved)
- [ ] Type something into a unit but DON'T save -> menu item.
- [ ] **Expected:** linting runs against the in-memory buffer (not the
      on-disk file), so unsaved edits are reflected in the findings.

## 16. Test Connection...
- [ ] Menu item.
- [ ] **Expected:** a dialog reports whether `drag-lint.exe` / the LSP is
      reachable and its version. Use this first if other items misbehave.

## 17. Open Plugin Log
- [ ] Menu item.
- [ ] **Expected:** the plugin's log file opens (in the editor or default
      viewer) - useful when diagnosing any of the above.

---

## 18. Related IDE surfaces (not under the submenu)

- [ ] **18.1 Tools -> Options -> drag-lint:** a native options page exists
      (INTAAddInOptions) for plugin settings.
- [ ] **18.2 Dwell hover:** rest the mouse on an identifier ~1.6 s (don't click)
      -> a short LSP summary popup appears; moving away dismisses it. It should
      NOT fight the menu's richer Hover (step 1).
- [ ] **18.3 Keyboard shortcuts:** the plugin registers keystrokes for common
      actions (hover/completion/etc.). Confirm they fire without the menu.
- [ ] **18.4 Open-source from the graph viewer:** with the viewer running
      (`drag_lint_graph.exe --db ...`), click a member -> the IDE jumps to the
      exact line via the pipe. (Lands on the right line/file = the recent guard
      working; needs the rebuilt BPL.)

---

## 19. Lifecycle (do last)

- [ ] **19.1** Uninstall the package (Install Packages -> uncheck) -> the IDE
      does NOT crash and the `drag-lint` submenu disappears cleanly. (Earlier
      versions had unload AVs; this checks the teardown.)
- [ ] **19.2** Re-install -> the submenu returns and items work again.

---

## How to report back
Per failing step: the number, what you saw, and any text from **Open Plugin Log**
(step 17) or the Messages pane. That pins each issue fast.
