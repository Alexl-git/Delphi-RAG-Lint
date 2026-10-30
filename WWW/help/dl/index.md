---
id: index
title: drag-lint help
summary: Every drag-lint feature, by group.
product: DL
---

# drag-lint help

drag-lint is developed alongside Micronite, our quality and production-control software ([www.htrmicronite.com](https://www.htrmicronite.com)).

## Indexing

Build and maintain the per-project and library indexes.

| Feature | What it does | Since |
| --- | --- | --- |
| [Auto-Document Whole Project](features/auto-document-whole-project.md) | Writes DocInsight documentation into every public declaration a project owns | 0.1.0-alpha |
| [Include-file indexing and IF evaluation](features/inc-indexing.md) | Include files are indexed under the active build, value defines and IF expressions are evaluated, and an undecidable IF is reported as a pp-unresolved-if hint | 1.37.0-alpha |
| [Index a project against its active build config](features/index-build-config.md) | Parses a project index against the project's active build config (the .dproj Config marker or delphilsp.json) instead of a fixed Release, with an override flag | 1.35.1-alpha |
| [migrate-dbs](features/migrate-dbs.md) | Moves project index databases into each project's own D-RAG folder, matching the current index layout | 1.3.0-alpha |
| [pp-profile](features/pp-profile.md) | Diagnostic that prints the resolved preprocessor define profile for a project, one symbol per line | 0.92.0-alpha |
| [purge-locals](features/purge-locals.md) | A size escape hatch for an index database that has grown too large: it drops local-variable and parameter symbols and runs VACUUM to reclaim space | 0.91.0-alpha |
| [Rebuild Index for This Project](features/rebuild-index-for-this-project.md) | Walks a project's .dproj compile closure and (re)builds its index | 0.2.0-alpha |
| [register-project](features/register-project.md) | Add a new project to the manifest so index --all and the IDE can see it | 1.20.4-alpha |
| [schema](features/schema.md) | Prints the live schema of an index database: schemaversion, every table and column, and row counts | 0.95.0-alpha |
| [Show Resolved DBs (debug)](features/show-resolved-dbs-debug.md) | Prints which database(s) drag-lint would actually use for a given project, file, or platform, without running a real query | 0.60.0-alpha |

## Search and navigation

Find symbols, callers, callees, text and types in the index.

| Feature | What it does | Since |
| --- | --- | --- |
| [call-path](features/call-path.md) | Finds the shortest resolved call path from one symbol to another | 0.91.0-alpha |
| [Class Surface](features/class-surface.md) | Shows the public surface of a class: its members and signatures, without the method bodies | 0.1.0-alpha |
| [Compiler Hints](features/compiler-hints.md) | Uses query hints to surface compiler hint/warning findings that have been imported into the index, filtered by code or severity | 0.1.0-alpha |
| [query --concept](features/concept-search.md) | Ranked BM25 concept search over identifier words and doc-comment prose | 1.38.0-alpha |
| [context](features/context.md) | Returns a compact context bundle for a symbol -- its doc comment, class surface (signatures), the target's own body, and a capped list of callers | 0.6.0-alpha |
| [find-callees](features/find-callees.md) | Lists the resolved outgoing calls of one routine, plus the library-bound ones | 0.91.0-alpha |
| [Find Undocumented (public)](features/find-undocumented-public.md) | Uses query find to list indexed symbols filtered by documentation state, kind, or visibility | 0.1.0-alpha |
| [find-unit](features/find-unit.md) | Finds which indexed unit declares a symbol, and adds that unit to a file's uses clause | 0.69.0-alpha |
| [Find Usages](features/find-usages.md) | Lists every reference to the symbol under the editor caret across the indexed project | 0.33.0-alpha |
| [Find Usages](features/find-usages-context.md) | Lists references to the symbol represented by a Structure-tree node | 0.33.0-alpha |
| [Gain (counted savings)](features/gain-usage-log.md) | Sums the per-user usage log: tokens returned versus source bytes avoided, per verb and per day | 1.38.0-alpha |
| [Go to Declaration](features/go-to-declaration.md) | Jumps the editor caret to the declaration of the symbol represented by a Structure-tree node | 0.43.0-alpha |
| [Go to Definition](features/go-to-definition.md) | Jumps the editor caret to the declaration of the symbol under the cursor | 0.47.0-alpha |
| [Go to Implementation](features/go-to-implementation.md) | Jumps the editor caret to the implementation of the symbol represented by a Structure-tree node | 0.43.0-alpha |
| [helpers-of](features/helpers-of.md) | Lists record/class helper edges targeting a given type, anywhere in the index | 0.94.0-alpha |
| [Hover at Cursor](features/hover-at-cursor.md) | Shows a hover card for the symbol under the editor caret: signature, declared type, documentation, and callers | 0.7.0-alpha |
| [outline](features/outline.md) | Prints the file-scoped symbol outline for one Pascal unit | 0.86.0-alpha |
| [query ancestors](features/query-ancestors.md) | Resolves the transitive class/interface hierarchy of a type | 0.1.0-alpha |
| [query descendants](features/query-descendants.md) | The reverse of query ancestors: lists every class that descends from a given ancestor, across all scanned databases | 1.2.2-alpha |
| [query find-callers](features/query-find-callers.md) | Lists callers of a routine by name, with an option to restrict results to precise, resolved callers | 0.1.0-alpha |
| [query --kind --all](features/query-kind-all.md) | Lists every symbol of one kind -- every unit, every class, every enum -- with no name, no doc clause and no row cap | 1.19.1-alpha |
| [query --name-like](features/query-name-like.md) | Case-insensitive substring search over symbol names | 1.8.0-alpha |
| [query --text --near](features/query-text-near.md) | Keeps only text hits in routines within N call-graph hops of a symbol | 1.38.0-alpha |
| [query type-usage](features/query-type-usage.md) | Answers one question, of a list of type names, about one file | 0.1.0-alpha |
| [query typecat](features/query-typecat.md) | Resolves a type's category -- float, string, class, interface, and so on | 0.66.0-alpha |
| [query unit-usage](features/query-unit-usage.md) | Shows which files reference a unit, or - with --in - which of its exports one file actually uses | 1.12.0-alpha |
| [Show Completion](features/show-completion.md) | Shows an index-backed completion list at the editor caret | 0.21.0-alpha |
| [Show Signature Help](features/show-signature-help.md) | Shows parameter help for the call being typed at the editor caret | 0.21.0-alpha |
| [Show Structure](features/show-structure.md) | Shows a structural outline of the current unit | 0.30.0-alpha |
| [Symbol Search](features/symbol-search.md) | Searches symbols by name across the indexed projects | 0.1.0-alpha |
| [Symbol Slice](features/symbol-slice.md) | Shows the slice of code relevant to one symbol: its declaration, body, and immediate context | 0.17.0-alpha |
| [Type at Cursor](features/type-at-cursor.md) | Resolves the static type of the expression under the editor caret | 0.19.0-alpha |
| [usages](features/usages.md) | Finds usage sites of a named symbol, with a choice of report width | 0.33.0-alpha |
| [wiki](features/wiki.md) | Looks up the dl:wiki concept topics a team has written into their own doc comments, and routes a human phrase to the code that implements it | 1.7.0-alpha |

## Linting

Rules, autofix, suppression markers and project-wide checks.

| Feature | What it does | Since |
| --- | --- | --- |
| [Autofix for fixable rules](features/autofix-wave.md) | lint --fix repairs findings of the 111 fixable rules; --json reports per finding whether it was applied; lint accepts a folder | 1.37.0-alpha |
| [Compliance labels (CWE, CERT, MISRA)](features/compliance-labels.md) | Rules carry CWE / CERT / MISRA ids; --labels prints them, rules --standard filters by standard, JSON gains a compliance field | 1.37.0-alpha |
| [Copy All Diagnostics](features/copy-all-diagnostics.md) | Puts every lint finding for the current unit onto the clipboard, starting from the Structure form | 0.1.0-alpha |
| [Copy Diagnostics (Current File)](features/copy-diagnostics-current-file.md) | Puts the current file's lint findings onto the clipboard | 0.1.0-alpha |
| [Copy Selected Diagnostics](features/copy-selected-diagnostics.md) | Copies only the Diagnostics rows selected in the Structure form (Ctrl/Shift-click, Ctrl+C) to the clipboard | 1.28.3-alpha |
| [drag-lint: Project Rules](features/drag-lint-project-rules.md) | Right-click a project in the Project Manager to make it the active project and open its Lint Options tab in the drag-lint dock | 0.95.0-alpha |
| [exceptions-sync](features/exceptions-sync.md) | Declare one exception class per distinct raise Exception.Create message, then rewrite the raise sites | 1.8.0-alpha |
| [Fix all in project](features/fix-all-in-project.md) | Applies autofixes for every fixable finding across the whole project, starting from the Structure form | 0.61.0-alpha |
| [Fix all in unit](features/fix-all-in-unit.md) | Applies autofixes for every fixable finding in the current unit, starting from the Structure form | 0.1.0-alpha |
| [Fix all reliability (1.31.3)](features/fix-all-reliability.md) | Fix all no longer drops every rename for library-root members, shows a wait cursor and refuses a second fix, and keeps E-prefixed exception classes | 1.31.3-alpha |
| [Fix it](features/fix-it.md) | Applies the fix for the single lint finding on a Structure-tree node; an unused unit is removed or moved to implementation by compiling | 0.1.0-alpha |
| [Format Whole Project with YADF](features/format-whole-project-with-yadf.md) | Runs YADF formatting across a project's files, with indexing involved as part of the same action | 0.1.0-alpha |
| [Format with YADF](features/format-with-yadf.md) | Reformats one Pascal unit by driving the external YADF formatter | 0.16.0-alpha |
| [Gap-wave lint rules](features/gap-wave-rules.md) | About 50 new lint rules (bug patterns, dead code, data flow, platform, structure) added in the 1.37.0 gap wave | 1.37.0-alpha |
| [Lint Buffer (Unsaved)](features/lint-buffer-unsaved.md) | Lints the current editor buffer's in-memory content, including unsaved edits, without writing it to disk first | 0.1.0-alpha |
| [lint-project](features/lint-project.md) | Runs project-scoped structural lint rules against an index -- checks such as god-class, unused-public-symbol | 0.48.0-alpha |
| [Lint rules](features/lint-rules.md) | Every lint rule the engine ships, imported from rules --json | 0.2.0-alpha |
| [lint-tree](features/lint-tree.md) | Answers one question lint-all cannot: does an interface edit to this unit reach any dependent? | 1.11.0-alpha |
| [Rename across every project that compiles a shared unit](features/multi-project-rename.md) | A naming fix on a unit several project indexes own renames it in every owner or in none, after an IDE confirmation listing the projects | 1.29.0-alpha |
| [Rescan this unit](features/rescan-this-unit.md) | Re-indexes the active project and re-lints the current unit on demand, so the Diagnostics panel drops findings already fixed | 1.28.3-alpha |
| [Run AST Checks](features/run-ast-checks.md) | Runs drag-lint's AST-level checks against a file | 0.31.0-alpha |
| [Run Diagnostics (didSave)](features/run-diagnostics-didsave.md) | Runs drag-lint's diagnostics pass on a file automatically when it is saved, mirroring the LSP textDocument/didSave notification | 0.22.0-alpha |
| [Run Lint All (Full Report)](features/run-lint-all-full-report.md) | Runs the whole rule catalog against a project's indexed code and reports every surviving finding -- the overall project health check | 0.61.0-alpha |
| [Taint analysis (SQL, command, path)](features/taint-analysis.md) | taint-sql-injection, taint-command-injection and taint-path-traversal follow index data_flows facts from a source to a sink | 1.37.0-alpha |
| [Target compiler (--target-compiler)](features/target-compiler.md) | Names the Delphi the code is for: lint drops advice needing a newer compiler; index parses `VER<N>0` / `CompilerVersion` branches for it | 1.38.0-alpha |
| [Type-level dl:ok review](features/type-level-review-marker.md) | One dl:ok on an enum type declaration reviews every unused-enum-value or enum-ordinal-cast finding of that type, in any unit | 1.38.0-alpha |
| [type-name-prefix: expected letter from the ancestor chain](features/type-name-prefix-origin.md) | type-name-prefix picks E or T from the ancestor chain (project, then library index); untraceable ancestors are an index gap; autofix uses the finding's letter | 1.31.4-alpha |

## Documentation

DocInsight comments generated from the index, and drift detection.

| Feature | What it does | Since |
| --- | --- | --- |
| [Doc Comment Stub (symbol)](features/doc-comment-stub-symbol.md) | Uses generate-docs to produce a doc-comment stub for one qualified symbol | 0.25.0-alpha |
| [doc-drift](features/doc-drift.md) | Diagnostic that computes deterministic doc-vs-code drift findings for one symbol | 0.93.0-alpha |
| [doc-forget](features/doc-forget.md) | Reap or rename the project tags on inbound documentation facts; a dry run unless told to apply | 1.17.0-alpha |
| [document-all](features/document-all.md) | Documents every public declaration in every indexed unit, with no project scope | 0.93.0-alpha |
| [Document it](features/document-it.md) | Generates or repairs a managed DocInsight comment on the single symbol represented by a Structure-tree node | 0.90.0-alpha |
| [Document project](features/document-project.md) | Generates or repairs managed DocInsight comments for every public declaration of the active project, started from the Structure form right-click menu | 0.90.0-alpha |
| [Document unit](features/document-unit.md) | Generates or repairs managed DocInsight comments for every public declaration in the unit open in the active editor (facts-only) | 0.90.0-alpha |
| [Effect Summary Legend](features/effect-summary-legend.md) | The purity analysis writes a short token string for every routine it judges -- symbolfacts.effectsummary in the index | 1.16.0-alpha |
| [shared-unit](features/shared-unit.md) | Reads or extends the dl:shared marker on a unit, recording which projects share it | 1.10.0-alpha |
| [dl:wiki concept blocks](features/wiki-blocks-authoring.md) | The format of a dl:wiki block -- the concept notes the wiki verb reads | 1.7.0-alpha |

## Refactoring and code generation

Rename, extract, safe delete, uses cleanup and code stubs.

| Feature | What it does | Since |
| --- | --- | --- |
| [allow](features/allow.md) | Records a dl:ok review of one finding, so it stops being reported without being fixed | 0.54.0-alpha |
| [Allow this message](features/allow-this-message.md) | Records a dl:ok review of one finding, so it stops being reported without being fixed | 0.54.0-alpha |
| [create-enum-helper](features/create-enum-helper.md) | Generates a Byte-family record helper (ToByte/FromByte/ToInteger/ FromInteger/ToString/FromString) for an enum type | 0.94.0-alpha |
| [Create helper class](features/create-helper-class.md) | Generates a Byte-family record helper for an enum type represented by a Structure-tree node | 0.94.0-alpha |
| [extract-method](features/extract-method.md) | Pulls a run of statements out of a routine into a new method | 0.85.0-alpha |
| [Quick-Fix: Add Unit for Inline Hint (H2443) at Cursor](features/quick-fix-add-unit-for-inline-hint-h2443-at-cursor.md) | The same idea as the undeclared-identifier quick-fix, but for compiler hint H2443 -- an inline routine whose declaring unit is not in scope | 1.2.0-alpha |
| [Quick-Fix: Add Unit for Undeclared at Cursor (Ctrl+Alt+U)](features/quick-fix-add-unit-for-undeclared-at-cursor-ctrl-alt-u.md) | Finds which unit declares the identifier under the caret and adds that unit to the current unit's uses clause | 0.47.0-alpha |
| [Quick-Fix: Convert Public Field to Property at Cursor](features/quick-fix-convert-public-field-to-property-at-cursor.md) | Rewrites a public field under the caret as a property | 1.2.0-alpha |
| [Reconcile Project Members (.dpr/.dproj)](features/reconcile-project-members-dpr-dproj.md) | Lists every unit a project uses that is neither a project member nor in the library, judges each one (project unit or third-party) and fixes it either way | 1.18.0-alpha |
| [Rename Symbol](features/rename-symbol.md) | Renames a symbol across the whole indexed project | 0.24.0-alpha |
| [safe-delete](features/safe-delete.md) | Deletes a symbol if and only if it has zero references in the index | 0.69.0-alpha |
| [Unit Test Stub (symbol)](features/unit-test-stub-symbol.md) | Uses generate-test to produce a unit-test skeleton for one qualified symbol | 0.27.0-alpha |
| [Uses Audit -- interface->impl moves + unused (this unit)](features/uses-audit-interface-impl-moves-unused-this-unit.md) | For one unit, reports which uses entries could move from the interface section to implementation, and which are unused entirely | 0.43.0-alpha |
| [Uses Cleanup Preview (compiler-verified, this unit)](features/uses-cleanup-preview-compiler-verified-this-unit.md) | The removals a Uses Audit suggests, but verified by actually compiling | 0.43.0-alpha |
| [Uses & Deps Tab](features/uses-deps-tab.md) | Open the Uses & Deps tab to review uses-clause fixes and apply them | 1.12.0-alpha |

## Component conversion

Rule-driven migration of legacy component types.

| Feature | What it does | Since |
| --- | --- | --- |
| [convert-apply](features/convert-apply.md) | Locates .dfm component instances that match a #convert rule from a conversion-rules file and rewrites all five surfaces: declaration retype, uses-add | 1.2.0-alpha |
| [convert-apply #migrate (member, type and enum rename / DL_NONE)](features/convert-apply-migrate.md) | #migrate renames or DL_NONE-breaks a member at its .pas access sites; at file scope (or with a uses unit) it renames a type, enum or identifier | 1.22.0-alpha |
| [convert-scaffold](features/convert-scaffold.md) | Auto-generates a valid conversion-rules file from the real property trees of a from-type and a to-type | 1.1.0-alpha |
| [convert-validate](features/convert-validate.md) | Parses and validates a conversion-rules file (a reFind-superset DSL), checking its #link/#default paths against the real property trees | 1.1.0-alpha |
| [Progress window and busy guard](features/convrules-busy-guard.md) | ConvRulesEditor shows a cancellable progress window for long engine calls and refuses Save, Add, Convert and Delete while one runs | 1.35.0-alpha |
| [Convert progress](features/convrules-convert-progress.md) | ConvRulesEditor Convert tab: per-step progress (unit, book, phase, elapsed) on the status bar and the tab | 1.26.7-alpha |
| [Curate rule books](features/convrules-curate.md) | ConvRulesEditor: split, delete, merge and compose #convert blocks across rule books on disk | 1.20.0-alpha |
| [ConvRulesEditor](features/convrules-editor.md) | Visual rulebook editor for the conversion rules; its Convert tab reports StripDB value casts, cast sites to convert by hand and uses changes (engine 1.27) | 0.0.0 |
| [Rule book and source encoding](features/convrules-encoding.md) | ConvRulesEditor keeps each book's encoding, asks before a lossy save, and before a Convert whose rules a source cannot hold (raise it, fix the rules, or cancel) | 1.35.0-alpha |
| [Member migration (#migrate)](features/convrules-migrate-members.md) | ConvRulesEditor: write #migrate Old -> New or -> DL_NONE (one row, or DL_NONE for all selected rows) into the row's book, or via the block's Members list | 1.35.0-alpha |
| [Qualify #convert quick fix](features/convrules-qualify-fix.md) | ConvRulesEditor Convert tab: one click writes the engine's qualified #convert line (apply/1 qualify_fixes) into the open book | 1.31.5-alpha |
| [Reindex project](features/convrules-reindex-project.md) | ConvRulesEditor command: incremental index --project of the editor's project index, cancellable | 1.26.7-alpha |
| [Rule chains (single-pass warning, merge / split)](features/convrules-rule-chains.md) | ConvRulesEditor marks #convert chains, cycles, duplicate From types and unit swap chains on Save; offers merge into TA -> TC or split into stage books | 1.35.1-alpha |
| [Work list](features/convrules-work-list.md) | ConvRulesEditor tab: what the last Convert run's converted code still uses from the old components (engine pas_uses) | 1.28.2-alpha |
| [glyph-vacuum](features/glyph-vacuum.md) | Measure every streamed glyph or picture under a tree before writing a glyph rule | 1.15.0-alpha |
| [proptree](features/proptree.md) | Recursive deep-property enumerator for a class: flattens its own and inherited properties into dotted paths, recursing into class-typed properties | 1.1.0-alpha |

## Graphs and reports

Call graphs, dependency reports, dead code, tester spreadsheets.

| Feature | What it does | Since |
| --- | --- | --- |
| [butterfly](features/butterfly.md) | Composes a symbol's callers (upward wing) and callees (downward wing) into one combined chart in a single command | 0.99.0-alpha |
| [Call Graph (Butterfly)](features/call-graph-butterfly.md) | Shows callers and callees of one symbol together in a single "butterfly" view | 0.96.0-alpha |
| [callgraph](features/callgraph.md) | Prints an N-deep resolved call tree for a symbol, in either direction | 0.91.0-alpha |
| [Circular Dependency Report (worked example)](features/circular-dependency-report.md) | A worked example: a real four-unit uses cycle, and the report drag-lint produces for it | 1.4.0-alpha |
| [Circular Uses Report (cycles + fix plan)](features/circular-uses-report-cycles-fix-plan.md) | Finds uses cycles among indexed units and, on request, proposes a followable refactoring plan to break them | 0.43.0-alpha |
| [Cycles fix (mechanical, compile-gated)](features/cycles-fix.md) | Plans, compile-gates and (with --apply) writes the mechanical fix of one circular uses group, verified against the predicted cycles output | 1.33.0-alpha |
| [deps-report](features/deps-report.md) | Produces a third-party dependency rollup from an index: which external units/libraries an indexed codebase depends on | 0.95.0-alpha |
| [Export Enums (Delphi const)](features/export-enums-delphi-const.md) | Uses export enums with --format delphi-const to dump indexed enum types as Delphi const declarations | 0.6.0-alpha |
| [Export Graph (DOT)](features/export-graph-dot.md) | Uses graph to export the indexed call/reference graph in DOT format, either whole or rooted at a name substring | 0.6.0-alpha |
| [Export to Obsidian](features/export-to-obsidian.md) | Uses export obsidian to write the indexed project out as a set of Obsidian vault markdown pages | 0.6.0-alpha |
| [Find Dead Code](features/find-dead-code.md) | Scans the index for code with no references -- candidates to delete | 0.25.0-alpha |
| [Forms for testers (CSV)](features/generate-test-helper-csv.md) | A CSV of a project's forms, one row per form, telling a tester how to reach each one from the main form | 0.44.0-alpha |
| [Impact / Blast Radius (symbol)](features/impact-blast-radius-symbol.md) | Reports what would be affected if a chosen symbol changes -- the set of code to retest | 0.17.0-alpha |
| [Code-built menu tree and registry drift](features/menu-tree.md) | The menu tree a Delphi program builds in code, read statically, and a check that the registered menu paths still match it | 1.33.0-alpha |
| [Reverse Call Tree (clickable, Messages window)](features/reverse-call-tree-clickable-messages-window.md) | The same reverse call tree, rendered into the IDE's Messages window so each line navigates to the caller | 0.98.0-alpha |
| [Reverse Call Tree (who calls this, N-deep)](features/reverse-call-tree-who-calls-this-n-deep.md) | Builds the tree of callers of a chosen symbol, transitively, to a chosen depth | 0.96.0-alpha |
| [Scan TODOs / FIXMEs](features/scan-todos-fixmes.md) | Scans source for TODO/FIXME/HACK/XXX/REVIEW/NOTE markers | 0.12.0-alpha |
| [Show in Call Graph](features/show-in-call-graph.md) | Opens the call graph rooted at the symbol represented by a Structure-tree node | 0.96.0-alpha |
| [Show Wiring (Spring4D DI + DFM events)](features/show-wiring-spring4d-di-dfm-events.md) | Surfaces bindings the compiler does not make obvious: Spring4D container registrations and DFM event hookups for a type | 0.21.0-alpha |
| [Top Symbols (fan-in)](features/top-symbols-fan-in.md) | Ranks indexed symbols by fan-in -- how many places reference them | 0.6.0-alpha |
| [Uses Report (CSV)](features/uses-report-csv.md) | Exports the project's unit-dependency data as a CSV file | 0.40.5-alpha |

## Diagrams and charts

Ask a question about a symbol and get a clickable chart.

| Feature | What it does | Since |
| --- | --- | --- |
| [ask](features/ask.md) | Ask one report question and print the answer as text | 1.30.0-alpha |
| [Where the charts find Graphviz](features/chart-engine-dot-lookup.md) | The charts find dot.exe by DRAGLINT_DOT, settings.json, the installed layout, PATH, then the shared default | 1.26.1-alpha |
| [Chart questions](features/chart-questions.md) | Every chart question of the Reports submenu and drag-lint ask, imported from REPORT_QUESTIONS | 1.20.2-alpha |
| [Charts and the IDE](features/charts-and-the-ide.md) | Ask a chart question, open the answer, read a round-trip trace, jump to RAD Studio | 1.20.1-alpha |
| [Compare a report with current code](features/compare.md) | Reruns a saved or pasted report and shows before / delta / after | 1.28.0-alpha |
| [Click-to-source: the draglint:// handler](features/protocol-handler.md) | Registers draglint:// so a chart row opens its line in RAD Studio; a GUI helper exe, no PowerShell | 1.31.0-alpha |

## Compiler integration

Compile, fold compiler output into findings, preprocess.

| Feature | What it does | Since |
| --- | --- | --- |
| [Add Missing Units to uses (whole unit)](features/add-missing-units-to-uses-whole-unit.md) | The whole-unit form of the undeclared-identifier quick-fix: resolves every unresolved name in a unit at once and adds the units that declare them | 0.43.0-alpha |
| [Compile Buffer (unsaved)](features/compile-buffer-unsaved.md) | Compiles a project with the current editor buffer's unsaved content in place of its file on disk, from a temporary shadow folder, without writing any real file | 0.47.0-alpha |
| [compile-check](features/compile-check.md) | Runs a compiler-backed check against a single Delphi project (.dproj) or source file (.pas) and reports the result | 0.26.0-alpha |
| [Compile Dependents](features/compile-dependents.md) | Check the units that depend on the one being edited now, instead of waiting for the automatic quiet-period pass (lint-tree tier 3) | 1.11.0-alpha |
| [Compile & Diagnose](features/compile-diagnose.md) | Compiles a project or unit and folds the compiler's errors and warnings into drag-lint findings | 0.26.0-alpha |
| [Full Compile Sweep](features/full-compile-sweep.md) | Recompiles every unit of a project (a forced full build, refresh-findings --full) and refreshes its stored compiler findings | 1.2.0-alpha |
| [ghost-check](features/ghost-check.md) | Compiles a project with one or more units' content temporarily replaced by their unsaved editor buffers, then restores the original files unchanged | 1.8.0-alpha |
| [ghost-recover](features/ghost-recover.md) | Scans a project's hidden D-RAG folder for recovery journals left behind when a ghost-check overlay was interrupted by a crash | 0.64.1-alpha |
| [Import Build Log](features/import-build-log.md) | Parses an external dcc or msbuild build log and folds its errors and warnings into drag-lint's stored findings | 0.8.0-alpha |
| [preprocess-file](features/preprocess-file.md) | Diagnostic that prints a file's {$IFDEF}-resolved source to stdout under a given define set | 0.92.0-alpha |
| [project-facts](features/project-facts.md) | Report what the build does: defines that are on and what sets each, imports, output paths and packages | 1.20.0-alpha |
| [Recover Buffer-Compile Files](features/recover-buffer-compile-files.md) | Restores any file left holding unsaved-buffer content after a Compile Buffer (unsaved) run was interrupted (for example by a crash) | 0.47.0-alpha |

## Database and Firebird

SQL scripts, live schema snapshots, ORM links.

| Feature | What it does | Since |
| --- | --- | --- |
| [fb-snapshot](features/fb-snapshot.md) | Connects to a Firebird database and captures a snapshot into a sqlite index | 0.40.5-alpha |
| [link-orm](features/link-orm.md) | Links a project's code index to a SQL index so ORM-style relationships between Delphi symbols and SQL objects can be resolved across both | 0.40.5-alpha |

## Editor integration

The RAD Studio plugin, the language server, MCP and workspaces.

| Feature | What it does | Since |
| --- | --- | --- |
| [drag-lint](features/drag-lint.md) | This page documents the "View > Tool Windows > drag-lint" menu entry -- the main drag-lint dockable tool window | 0.42.0-alpha |
| [drag-lint Graph](features/drag-lint-graph.md) | This page documents the "View > Tool Windows > drag-lint Graph" menu entry -- the drag-lint graph viewer | 0.43.0-alpha |
| [drag-lint Graph (dockable)](features/drag-lint-graph-dockable.md) | Opens the drag-lint graph viewer as a dockable window inside the IDE, so it can sit beside Structure | 0.43.0-alpha |
| [drag-lint Options](features/drag-lint-options.md) | The plugin's settings dialog for drag-lint: lets you browse and toggle the lint rule catalog | 0.95.0-alpha |
| [drag-lint Panel (dockable)](features/drag-lint-panel-dockable.md) | Opens the main drag-lint dockable tool window inside the IDE | 0.42.0-alpha |
| [Help line (DL page)](features/ide-help-line.md) | Type part of a feature name on the DL page, pick a match (with its menu path) and open that feature's help page at the configured help root | 1.33.0-alpha |
| [IDE Menu Reference](features/ide-menu-reference.md) | What every item in the drag-lint menu does | 1.4.0-alpha |
| [ide-release](features/ide-release.md) | Asks a running drag-lint Delphi IDE plugin not to respawn its drag-lint.exe child processes for a while -- and to drop the running one on its next request | 1.13.0-alpha |
| [init: one command from a project to a wired AI client](features/init-wiring.md) | Registers a project in the manifest, indexes it, finds its index and wires Claude Code, VS Code and Cursor to serve it, in one command | 1.38.0-alpha |
| [Installation](features/installation.md) | Getting the CLI, the IDE plugin, or the LSP running | 0.21.0-alpha |
| [lsp](features/lsp.md) | Starts the LSP (Language Server Protocol) stdio server | 0.6.0-alpha |
| [LSP full rule set on save](features/lsp-full-rules.md) | Runs the full lint rule set on save so the editor shows what the CLI shows | 1.33.0-alpha |
| [LSP protocol extensions](features/lsp-protocol-extensions.md) | Answers outline, implementation, rename, code lens, semantic tokens, inlay hints and commands from the index | 1.33.0-alpha |
| [LSP proxy merge](features/lsp-proxy-merge.md) | Merges drag-lint diagnostics, completion, hover and definition into a DelphiLSP proxy session | 1.33.0-alpha |
| [Switch VS Code Delphi MCP entry](features/lsp-switch-vscode.md) | Turns the VS Code Delphi MCP entry off and on with a backup | 1.33.0-alpha |
| [Register the MCP server (Claude Code, VS Code, Cursor)](features/mcp-config-writer.md) | Adds drag-lint serve to Claude Code, VS Code and Cursor MCP config: merged, backed up, idempotent, removable | 1.26.1-alpha |
| [MCP server](features/mcp-server.md) | Exposes the index to MCP clients as 15 tools | 0.4.0-alpha |
| [Output encoding (--output-encoding)](features/output-encoding.md) | Chooses the bytes verbs write to stdout, stderr and --output files: ASCII with \uXXXX escapes (default), UTF-8 or UTF-16LE, never a BOM; lossy ascii warns once | 1.35.0-alpha |
| [project-context](features/project-context.md) | Writes or checks the `.dlcontext.json` file beside a project: platform, config and define set, with the .dproj SHA-1 for staleness | 1.38.0-alpha |
| [serve](features/serve.md) | Starts the MCP (Model Context Protocol) stdio server, for AI clients such as Claude or Cursor to query a drag-lint index | 0.4.0-alpha |
| [Setup installer](features/setup-installer.md) | One Inno Setup installer for the engine, Graphviz dot, the IDE plugin, ConvRulesEditor, drag-lint-graph and YADF | 1.28.3-alpha |
| [VS Code extension: Problems stay current](features/vscode-extension.md) | VS Code extension commands, and Problems that follow files an agent edits on disk | 1.38.0-alpha |
| [workspace add](features/workspace-add.md) | Registers a project file into a .drag-lint-workspace.json workspace config, so multi-project workspace commands know about it | 0.6.0-alpha |
| [workspace index](features/workspace-index.md) | Indexes every project registered in a .drag-lint-workspace.json workspace config in one pass | 0.6.0-alpha |
| [workspace status](features/workspace-status.md) | Reports the status of every project registered in a .drag-lint-workspace.json workspace config | 0.6.0-alpha |

## Maintenance and diagnostics

Which databases cover what, drift checks, raw dumps, self-tests.

| Feature | What it does | Since |
| --- | --- | --- |
| [About and Status](features/about-and-status.md) | The plugin's status window -- versions, connection health, and which indexes are actually in use | 0.15.0-alpha |
| [ambiguous-calls](features/ambiguous-calls.md) | Resolver-coverage diagnostic that reports call sites the engine could not pin to exactly one target -- unresolved or ambiguous calls | 0.91.0-alpha |
| [bench-context](features/bench-context.md) | Benchmarks the context command by building context bundles for a sample of symbols against a database | 0.18.0-alpha |
| [diff](features/diff.md) | Compares two index databases and reports what changed between them -- for example an index snapshot taken before and after a refactor | 0.13.0-alpha |
| [dump-call-edges](features/dump-call-edges.md) | Diagnostic that dumps every resolved call edge in the index as refid\|targetqname\|confidence rows | 0.91.0-alpha |
| [dump-refs](features/dump-refs.md) | Diagnostic that dumps every ref in a file together with its enclosingsymbolid attribution | 0.82.0-alpha |
| [Feature registry](features/feature-registry.md) | The machine-checked master list of every feature, and the generator of the index pages | 1.22.0-alpha |
| [info](features/info.md) | Prints engine self-info: version, build date, license (MIT), tree-sitter details, and capabilities | 0.19.0-alpha |
| [Library Drift Check](features/library-drift-check.md) | Flags registered library roots that have source on disk but nothing in the index | 0.47.0-alpha |
| [Maintenance](features/maintenance.md) | Indexes, the manifest, reindexing, and what to do when something looks wrong | 1.4.0-alpha |
| [Open Plugin Log](features/open-plugin-log.md) | Opens the drag-lint plugin's own log file | 0.39.0-alpha |
| [shutdown](features/shutdown.md) | Ask running engines (lsp, cycles --fix, index, lint-all) to stand down cleanly, so an index can be rebuilt or an engine replaced | 0.6.0-alpha |
| [sql](features/sql.md) | Runs one read-only SQL statement against an index database and prints the result set | 0.40.5-alpha |

## Uses and Dependencies

Which units a unit needs, where they go in uses, and the cycles they make.

| Feature | What it does | Since |
| --- | --- | --- |
| [Auto uses on save (VS Code)](features/auto-uses-on-save.md) | VS Code adds a missing unit to uses on save (source.addMissingImports); dropping an unused unit on save is opt-in and gated | 1.38.0-alpha |
| [Missing unit in uses (unit-missing-from-uses)](features/unit-missing-from-uses.md) | Lint rule: names the unit that declares an undeclared identifier and adds it to the interface or implementation uses clause, cycle-checked | 1.38.0-alpha |

