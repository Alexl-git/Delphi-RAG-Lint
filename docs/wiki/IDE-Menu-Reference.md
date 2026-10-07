# IDE Menu Reference

The plugin adds a top-level **`drag-lint`** menu to the RAD Studio menu bar (it
falls back to a submenu under *Tools* if the main menu is unavailable), plus two
entries under *View > Tool Windows*.

Every item spawns the `drag-lint.exe` CLI. If an item does nothing, start with
**About > Open Plugin Log** -- it records what was actually invoked. If the
menu's own caption reads **`drag-lint (!)`**, the LSP server is down; open
**About** and read the Connections group for the reason.

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

## Reports

Every report question of the chart pipeline (`charts\src\Ask-Report.ps1`), asked
from the IDE. Grouped by what you select; every item needs a current **(index)**.

What a click does:

1. **Picks the target.** For the caret groups, if the active unit has unsaved
   changes you are asked *Save all first?* (*Cancel* stops -- an unsaved buffer
   may not match the indexed line numbers). The caret is then resolved with
   `drag-lint typeat` to a qualified name (the bare identifier if it cannot be
   resolved). For a form control, `Unit.TForm.Control` is rewritten to the
   `<FormInstance>.<Control>` form the control questions take, read from the
   unit's DFM. The target is shown in an editable prompt before anything runs.
   *This project* items need no target; the *table or column* items prompt for
   a name.
2. **Runs in the background** through the plugin's job queue (the status bar
   shows it), as `pwsh -File Ask-Report.ps1 ... -In <active file> -Open`.
   Needs PowerShell 7 and the repository's `charts\src` two folders above the
   engine exe; if either is missing the item says so.
3. **Answers twice.** Charts open in your browser. The text answer is turned
   into a DocInsight `/// <remarks>` block -- 7-bit ASCII, wrapped under 100
   columns, `File.pas:line` anchors in parentheses, "+N more ... not shown" kept
   -- copied to the clipboard and shown in a small window with a *Copy* button.
   Paste it above the declaration it describes: it carries no autodoc marker,
   so Auto Doc leaves it alone.

If the question is refused (exit 1) or the indexes cannot be resolved (exit 2)
you see the script's reason. If an index is **stale** (exit 3) you see the
reindex command and are offered to run it as the background incremental index
job; ask again when it finishes.

**Routine at the cursor**

| Item | Question |
|---|---|
| **Callers and callees (butterfly chart)...** | [butterfly](ask-butterfly) |
| **Who calls this routine...** | [who-calls](ask-who-calls) |
| **What this routine calls...** | [what-it-calls](ask-what-it-calls) |
| **Call path from this routine to another...** | [path](ask-path) -- the caret gives routine A; you are then asked for routine B |
| **What this routine changes (side effects)...** | [effects](ask-effects) |
| **Which tables this routine touches...** | [touches-tables](ask-touches-tables) |
| **Which exceptions escape this routine...** | [exception-paths](ask-exception-paths) |
| **Does this routine leave the process...** | [crosses-boundary](ask-crosses-boundary) |
| **Where this protocol command travels...** | [protocol-trace](ask-protocol-trace) |
| **What a change here would break...** | [change-impact](ask-change-impact) |
| **Which tests reach this code...** | [tested-by](ask-tested-by) |

**Field, property or grid column at the cursor**

| Item | Question |
|---|---|
| **Who writes this field...** | [who-writes](ask-who-writes) |
| **Who reads this field...** | [who-reads](ask-who-reads) |
| **What feeds this control (back to the column)...** | [feeds-from](ask-feeds-from) |
| **Where this field lands in the database...** | [lands-where](ask-lands-where) |
| **Field round-trip (grid -> server -> SQL)...** | `round-trip` -- see [Field Round-Trip Report](Field-Round-Trip-Report) |

**Type at the cursor**

| Item | Question |
|---|---|
| **What this type exposes (class surface)...** | [class-surface](ask-class-surface) |
| **Ancestors and descendants (hierarchy)...** | [hierarchy](ask-hierarchy) |
| **Who registers and resolves this interface...** | [wiring](ask-wiring) |
| **Which handler runs on which event (form)...** | [event-wiring](ask-event-wiring) |
| **Form lifecycle (create -> show -> destroy)...** | [lifecycle](ask-lifecycle) |

**This unit**

| Item | Question |
|---|---|
| **Dependencies of this unit...** | [deps](ask-deps) -- the target is pre-filled with the active unit's name |

**This project**

| Item | Question |
|---|---|
| **Project architecture (layered zones)...** | [architecture](ask-architecture) |
| **Circular unit dependencies...** | [cycles](ask-cycles) |

**Table or column (typed name)**

| Item | Question |
|---|---|
| **Who uses this table or column...** | [consumers](ask-consumers) |
| **Where this database column is shown...** | [shown-where](ask-shown-where) |
| **Forms for testers (CSV)...** *(index)* | Under the *For testers* header, last on Reports. One spreadsheet row per form: the menu / ribbon / tab path from the main form, the control to click, whether it opens modally, how sure the tool is, and a blank *Tester result* column. See [Generate Test Helper CSV](Generate-Test-Helper-CSV). |

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

## Compile && Analysis

Below a separator, under a section header. Daily actions, which is why they sit
on the menu rather than behind the About window.

| Item | What it does |
|---|---|
| **Compile && Diagnose** | Compiles, then reports diagnostics together with compiler output. |
| **Compile Buffer (unsaved)** | Compiles the unsaved buffer -- the "ghost check", for errors that only exist in what you are typing. |

---

## About

| Item | What it does |
|---|---|
| **About** | Opens the [About and Status window](About-and-Status) -- versions, connection health, which indexes are actually in use, configuration warnings, process footprint, and the diagnostic actions listed below. |

The seven items that used to sit under a *Diagnostics && Tests* section header
are **no longer on the menu**. They are buttons on the About window, because
each one is reached when something is already wrong -- which is exactly when the
rest of that window's information is wanted too:

| Moved action | Now at |
|---|---|
| **Run Diagnostics (didSave)** | *About > Run Diagnostics (didSave)* |
| **Run AST Checks** | *About > Run AST Checks* |
| **Lint Buffer (Unsaved)** | *About > Lint Buffer (Unsaved)* |
| **Copy Diagnostics (Current File)** | *About > Copy Diagnostics (Current File)* |
| **Recover Buffer-Compile Files** | *About > Recover Buffer-Compile Files* |
| **Import Build Log...** | *About > Import Build Log...* |
| **Open Plugin Log** | *About > Open Plugin Log* |

---

## View > Tool Windows

| Item | What it does |
|---|---|
| **drag-lint** | The dockable panel. |
| **drag-lint Graph** | The dockable graph viewer. |

Both are also reachable from the top of the `drag-lint` menu. The plugin removes
any stale entries of the same name on load, so an earlier install cannot leave a
dead item that calls into an unloaded package.
