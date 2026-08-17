# IDE Menu Reference

The plugin adds a top-level **`drag-lint`** menu to the RAD Studio menu bar (it
falls back to a submenu under *Tools* if the main menu is unavailable), plus two
entries under *View > Tool Windows*.

Every item spawns the `drag-lint.exe` CLI. If an item does nothing, start with
**Open Plugin Log** at the bottom of the menu -- it records what was actually
invoked.

Items marked **(index)** need a current index for the active project. If results
look thin or stale, see [Maintenance](Maintenance).

---

## Pinned at the top

| Item | What it does |
|---|---|
| **Full Compile Sweep** | Recompiles all units, refreshes the stored compiler findings, then refreshes the open file. The most-used action, which is why it sits above everything else. |

## Panels

| Item | What it does |
|---|---|
| **drag-lint Panel (dockable)** | Opens the main dockable tool window. Also under *View > Tool Windows > drag-lint*. |
| **drag-lint Graph (dockable)** | Opens the graph viewer as a dockable window, so it can sit beside Structure. Also under *View > Tool Windows > drag-lint Graph*. Requires `drag_lint_graph.exe` deployed beside the BPL. |

## Everyday actions

| Item | What it does |
|---|---|
| **Hover at Cursor** *(index)* | The hover card for the symbol under the caret: signature, documentation, callers. |
| **Go to Definition** *(index)* | Jumps to the declaration of the symbol under the caret. |
| **Show Completion** *(index)* | Index-backed completion list at the caret. |
| **Show Signature Help** *(index)* | Parameter help for the call being typed. |
| **Find Usages...** *(index)* | All references to the symbol under the caret. |
| **Symbol Search...** *(index)* | Search symbols by name across the indexed projects. |
| **Show Structure** | Structural outline of the current unit. |
| **Rename Symbol...** *(index)* | Index-backed rename across the project. Review the preview: a rename is a source-wide edit. |
| **Format with YADF** | Formats the current unit with YADF. |
| **Format Whole Project with YADF...** | Formats every unit in the project. |
| **Generate Test Helper CSV...** | Exports a CSV used by the form/test helper tooling. |
| **drag-lint Options...** | The plugin's own options page (rule enablement, profiles, paths). |

---

## Uses && Dependencies

Everything about what a unit depends on and what depends on it.

| Item | What it does |
|---|---|
| **Circular Uses Report (cycles + fix plan)...** | Finds `uses` cycles and proposes an order of moves that breaks them. |
| **Uses Audit -- interface->impl moves + unused (this unit)...** | For the current unit: which `uses` entries could move from `interface` to `implementation`, and which are unused. |
| **Uses Cleanup Preview (compiler-verified, this unit)...** | The removals from the audit, **verified by compiling**, so a unit needed only for an inline or a `{$IF}` branch is not stripped. |
| **Reconcile Project Members (.dpr/.dproj)...** | Compares the project file's member list against what is on disk and in the closure. |
| **Uses Report (CSV)...** | The dependency data as CSV. |
| **Quick-Fix: Add Unit for Undeclared at Cursor** (`Ctrl+Alt+U`) | The identifier under the caret is undeclared: finds which unit declares it and adds that unit to `uses`. |
| **Quick-Fix: Add Unit for Inline Hint (H2443) at Cursor** | Same, for the inline-expansion hint -- an inline routine whose unit is not in scope. |
| **Quick-Fix: Convert Public Field to Property at Cursor** | Rewrites a public field as a property. |
| **Add Missing Units to uses (whole unit)...** | The whole-unit form: every unresolved name at once. |
| **Impact / Blast Radius (symbol)...** *(index)* | What is affected if this symbol changes -- the set to retest. |
| **Show Wiring (Spring4D DI + DFM events)...** *(index)* | Bindings the compiler does not make obvious: Spring4D container registrations and DFM event hookups. |
| **Reverse Call Tree (who calls this, N-deep)...** *(index)* | Callers, transitively, to a chosen depth. |
| **Reverse Call Tree (clickable, Messages window)...** *(index)* | The same tree in the IDE Messages window, so each line navigates. |
| **Call Graph (Butterfly)...** *(index)* | Callers and callees of one symbol together -- the butterfly view. |

## Inspect Symbol

| Item | What it does |
|---|---|
| **Class Surface...** *(index)* | The public surface of a class: members and signatures, without the bodies. |
| **Symbol Slice...** *(index)* | The slice of code relevant to one symbol -- declaration, body, and its immediate context. |
| **Type at Cursor** *(index)* | Resolves the static type of the expression under the caret. |

## Code Quality

| Item | What it does |
|---|---|
| **Run Lint All (Full Report)...** *(index)* | The full project lint: `.scm` rules, built-in AST checks, project-wide rules, class metrics, duplicate code and documentation drift. Writes a report file. |
| **Find Dead Code...** *(index)* | Symbols nothing references. |
| **Find Undocumented (public)...** *(index)* | Public declarations with no documentation comment. |
| **Scan TODOs / FIXMEs...** | TODO/FIXME/HACK comments across the project. |
| **Compiler Hints...** | The stored compiler findings, from the last sweep or an imported log. |
| **Top Symbols (fan-in)...** *(index)* | The most-depended-on symbols -- where a change ripples furthest. |

## Generate && Export

| Item | What it does |
|---|---|
| **Doc Comment Stub (symbol)...** *(index)* | A DocInsight comment skeleton for one symbol, with index-grounded facts. |
| **Auto-Document Whole Project...** *(index)* | Generates or refreshes managed documentation blocks across the project. **Writes to source files** -- commit or stash first. |
| **Unit Test Stub (symbol)...** | A test skeleton for the symbol. |
| **Export Enums (Delphi const)...** | Enumerations as Delphi constant declarations. |
| **Export Graph (DOT)...** *(index)* | The dependency/call graph in Graphviz DOT. |
| **Export to Obsidian...** *(index)* | Exports index knowledge as Obsidian-style linked notes. |

## Index && Maintenance

| Item | What it does |
|---|---|
| **Rebuild Index for This Project** | **Destructive by design.** Clears this project's index and re-parses its whole compile closure. Named "Rebuild", not "Reindex", so it cannot be confused with an incremental refresh. |
| **Show Resolved DBs (debug)...** | Which databases this project resolves to. The first thing to check when results come from somewhere unexpected. |
| **Library Drift Check...** | Compares the library index against the current Library/Browsing paths and reports what has moved -- run it after a third-party suite update. |

---

## Diagnostics && Tests (alpha)

Below a separator, under a section header. These are development and
troubleshooting aids rather than daily actions.

| Item | What it does |
|---|---|
| **Run Diagnostics (didSave)** | Runs the diagnostics pass the editor integration fires on save. |
| **Run AST Checks** | The built-in AST checks only, on the current file. |
| **Lint Buffer (Unsaved)** | Lints the editor buffer, including unsaved edits. |
| **Copy Diagnostics (Current File)** | Puts the current file's findings on the clipboard. |
| **Compile && Diagnose** | Compiles, then reports diagnostics together with compiler output. |
| **Compile Buffer (unsaved)** | Compiles the unsaved buffer -- the "ghost check", for errors that only exist in what you are typing. |
| **Recover Buffer-Compile Files** | Recovers the temporary files a buffer compile leaves behind if it is interrupted. |
| **Import Build Log...** | Loads an external build log so its errors become browsable findings. |
| **Open Plugin Log** | The plugin's own log -- **start here when a menu item misbehaves.** |

---

## View > Tool Windows

| Item | What it does |
|---|---|
| **drag-lint** | The dockable panel. |
| **drag-lint Graph** | The dockable graph viewer. |

Both are also reachable from the top of the `drag-lint` menu. The plugin removes
any stale entries of the same name on load, so an earlier install cannot leave a
dead item that calls into an unloaded package.
