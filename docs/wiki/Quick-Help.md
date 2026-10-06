# Quick Help

One line per feature, grouped as on [Features](Features), with the short help and the words people search for. Every line links the feature's own page; this page is generated from the feature registry and never edited by hand.

## Indexing

* **Auto-Document Whole Project** -- Writes DocInsight documentation into every public declaration a project owns. [More](Auto-Document-Whole-Project)
* **migrate-dbs** -- Moves project index databases into each project's own D-RAG folder, matching the current index layout. [More](migrate-dbs)
* **pp-profile** -- Diagnostic that prints the resolved preprocessor define profile for a project, one symbol per line. [More](pp-profile)
* **purge-locals** -- A size escape hatch for an index database that has grown too large: it drops local-variable and parameter symbols and runs VACUUM to reclaim space. [More](purge-locals)
* **Rebuild Index for This Project** -- Walks a project's .dproj compile closure and (re)builds its index. [More](Rebuild-Index-for-This-Project)
* **register-project** -- Add a new project to the manifest so index --all and the IDE can see it. [More](Features)
* **schema** -- Prints the live schema of an index database: schemaversion, every table and column, and row counts. [More](schema)
* **Show Resolved DBs (debug)** -- Prints which database(s) drag-lint would actually use for a given project, file, or platform, without running a real query. [More](Show-Resolved-DBs-debug)

## Search and navigation

* **call-path** -- Finds the shortest resolved call path from one symbol to another. [More](call-path)
* **Class Surface** -- Shows the public surface of a class: its members and signatures, without the method bodies. [More](Class-Surface)
* **Compiler Hints** -- Uses query hints to surface compiler hint/warning findings that have been imported into the index, filtered by code or severity. [More](Compiler-Hints)
* **context** -- Returns a compact context bundle for a symbol -- its doc comment, class surface (signatures), the target's own body, and a capped list of callers. [More](context)
* **Find Undocumented (public)** -- Uses query find to list indexed symbols filtered by documentation state, kind, or visibility. [More](Find-Undocumented-public)
* **Find Usages** -- Lists every reference to the symbol under the editor caret across the indexed project. [More](Find-Usages)
* **Find Usages** -- Lists references to the symbol represented by a Structure-tree node. [More](Find-Usages-context)
* **find-callees** -- Lists the resolved outgoing calls of one routine. [More](find-callees)
* **find-unit** -- Finds which indexed unit declares a symbol, and adds that unit to a file's uses clause. [More](find-unit)
* **Go to Declaration** -- Jumps the editor caret to the declaration of the symbol represented by a Structure-tree node. [More](Go-to-Declaration)
* **Go to Definition** -- Jumps the editor caret to the declaration of the symbol under the cursor. [More](Go-to-Definition)
* **Go to Implementation** -- Jumps the editor caret to the implementation of the symbol represented by a Structure-tree node. [More](Go-to-Implementation)
* **helpers-of** -- Lists record/class helper edges targeting a given type, anywhere in the index. [More](helpers-of)
* **Hover at Cursor** -- Shows a hover card for the symbol under the editor caret: signature, documentation, and callers. [More](Hover-at-Cursor)
* **outline** -- Prints the file-scoped symbol outline for one Pascal unit. [More](outline)
* **query --kind --all** -- Lists every symbol of one kind -- every unit, every class, every enum -- with no name, no doc clause and no row cap. [More](query-kind-all)
* **query --name-like** -- Case-insensitive substring search over symbol names. [More](query-name-like)
* **query ancestors** -- Resolves the transitive class/interface hierarchy of a type. [More](query-ancestors)
* **query descendants** -- The reverse of query ancestors: lists every class that descends from a given ancestor, across all scanned databases. [More](query-descendants)
* **query find-callers** -- Lists callers of a routine by name, with an option to restrict results to precise, resolved callers. [More](query-find-callers)
* **query type-usage** -- Answers one question, of a list of type names, about one file. [More](query-type-usage)
* **query typecat** -- Resolves a type's category -- float, string, class, interface, and so on. [More](query-typecat)
* **query unit-usage** -- Answers one question, about one unit and one file. [More](query-unit-usage)
* **Show Completion** -- Shows an index-backed completion list at the editor caret. [More](Show-Completion)
* **Show Signature Help** -- Shows parameter help for the call being typed at the editor caret. [More](Show-Signature-Help)
* **Show Structure** -- Shows a structural outline of the current unit. [More](Show-Structure)
* **Symbol Search** -- Searches symbols by name across the indexed projects. [More](Symbol-Search)
* **Symbol Slice** -- Shows the slice of code relevant to one symbol: its declaration, body, and immediate context. [More](Symbol-Slice)
* **Type at Cursor** -- Resolves the static type of the expression under the editor caret. [More](Type-at-Cursor)
* **usages** -- Finds usage sites of a named symbol, with a choice of report width. [More](usages)
* **wiki** -- Looks up the dl:wiki concept topics a team has written into their own doc comments, and routes a human phrase to the code that implements it. [More](wiki)

## Linting

* **Copy All Diagnostics** -- Puts every lint finding for the current unit onto the clipboard, starting from the Structure form. [More](Copy-All-Diagnostics)
* **Copy Diagnostics (Current File)** -- Puts the current file's lint findings onto the clipboard. [More](Copy-Diagnostics-Current-File)
* **drag-lint: Project Rules** -- Shows the catalog of lint rules in the context of a specific project. [More](drag-lint-Project-Rules)
* **exceptions-sync** -- Declare one exception class per distinct raise Exception.Create message, then rewrite the raise sites. [More](Features)
* **Fix all in project** -- Applies autofixes for every fixable finding across the whole project, starting from the Structure form. [More](Fix-all-in-project)
* **Fix all in unit** -- Applies autofixes for every fixable finding in the current unit, starting from the Structure form. [More](Fix-all-in-unit)
* **Fix it** -- Applies the autofix for the single lint finding represented by a Structure-tree node. [More](Fix-it)
* **Format Whole Project with YADF** -- Runs YADF formatting across a project's files, with indexing involved as part of the same action. [More](Format-Whole-Project-with-YADF)
* **Format with YADF** -- Reformats one Pascal unit by driving the external YADF formatter. [More](Format-with-YADF)
* **Lint Buffer (Unsaved)** -- Lints the current editor buffer's in-memory content, including unsaved edits, without writing it to disk first. [More](Lint-Buffer-Unsaved)
* **Lint rules** -- 189 rules, 23 fixable. Every lint rule the engine ships, imported from rules --json. [More](rules)
* **lint-project** -- Runs project-scoped structural lint rules against an index -- checks such as god-class, unused-public-symbol. [More](lint-project)
* **lint-tree** -- Answers one question lint-all cannot: does an interface edit to this unit reach any dependent?. [More](lint-tree)
* **Run AST Checks** -- Runs drag-lint's AST-level checks against a file. [More](Run-AST-Checks)
* **Run Diagnostics (didSave)** -- Runs drag-lint's diagnostics pass on a file automatically when it is saved, mirroring the LSP textDocument/didSave notification. [More](Run-Diagnostics-didSave)
* **Run Lint All (Full Report)** -- Runs the whole rule catalog against a project's indexed code and reports every surviving finding -- the overall project health check. [More](Run-Lint-All-Full-Report)

## Documentation

* **dl:wiki concept blocks** -- The format of a dl:wiki block -- the concept notes the wiki verb reads. [More](Wiki-Blocks-Authoring)
* **Doc Comment Stub (symbol)** -- Uses generate-docs to produce a doc-comment stub for one qualified symbol. [More](Doc-Comment-Stub-symbol)
* **doc-drift** -- Diagnostic that computes deterministic doc-vs-code drift findings for one symbol. [More](doc-drift)
* **doc-forget** -- Reap or rename the project tags on inbound documentation facts; a dry run unless told to apply. [More](Features)
* **Document it** -- Generates or repairs a managed DocInsight comment on the single symbol represented by a Structure-tree node. [More](Document-it)
* **Document project** -- Generates or repairs managed DocInsight comments for every public declaration the project owns, starting from a Structure-tree node's project. [More](Document-project)
* **Document unit** -- Generates or repairs managed DocInsight comments for every public declaration in the unit represented by a Structure-tree node (facts-only). [More](Document-unit)
* **document-all** -- Documents every public declaration in every indexed unit, with no project scope. [More](document-all)
* **Effect Summary Legend** -- The purity analysis writes a short token string for every routine it judges -- symbolfacts.effectsummary in the index. [More](Effect-Summary-Legend)
* **shared-unit** -- Reads or extends the dl:shared marker on a unit, recording which projects share it. [More](shared-unit)

## Refactoring and code generation

* **Allow this message** -- Records a dl:ok review of one finding, so it stops being reported without being fixed. [More](Allow-this-message)
* **allow** -- Records a dl:ok review of one finding, so it stops being reported without being fixed. [More](allow)
* **Create helper class** -- Generates a Byte-family record helper for an enum type represented by a Structure-tree node. [More](Create-helper-class)
* **create-enum-helper** -- Generates a Byte-family record helper (ToByte/FromByte/ToInteger/ FromInteger/ToString/FromString) for an enum type. [More](create-enum-helper)
* **extract-method** -- Pulls a run of statements out of a routine into a new method. [More](extract-method)
* **Quick-Fix: Add Unit for Inline Hint (H2443) at Cursor** -- The same idea as the undeclared-identifier quick-fix, but for compiler hint H2443 -- an inline routine whose declaring unit is not in scope. [More](Quick-Fix-Add-Unit-for-Inline-Hint-H2443-at-Cursor)
* **Quick-Fix: Add Unit for Undeclared at Cursor (Ctrl+Alt+U)** -- Finds which unit declares the identifier under the caret and adds that unit to the current unit's uses clause. [More](Quick-Fix-Add-Unit-for-Undeclared-at-Cursor-Ctrl-Alt-U)
* **Quick-Fix: Convert Public Field to Property at Cursor** -- Rewrites a public field under the caret as a property. [More](Quick-Fix-Convert-Public-Field-to-Property-at-Cursor)
* **Reconcile Project Members (.dpr/.dproj)** -- Compares a project file's declared member list against what is on disk and in the compile closure. [More](Reconcile-Project-Members-dpr-dproj)
* **Rename Symbol** -- Renames a symbol across the whole indexed project. [More](Rename-Symbol)
* **safe-delete** -- Deletes a symbol if and only if it has zero references in the index. [More](safe-delete)
* **Unit Test Stub (symbol)** -- Uses generate-test to produce a unit-test skeleton for one qualified symbol. [More](Unit-Test-Stub-symbol)
* **Uses & Deps Tab** -- Open the Uses & Deps tab to review uses-clause fixes and apply them. [More](Features)
* **Uses Audit -- interface->impl moves + unused (this unit)** -- For one unit, reports which uses entries could move from the interface section to implementation, and which are unused entirely. [More](Uses-Audit-interface-impl-moves-unused-this-unit)
* **Uses Cleanup Preview (compiler-verified, this unit)** -- The removals a Uses Audit suggests, but verified by actually compiling. [More](Uses-Cleanup-Preview-compiler-verified-this-unit)

## Component conversion

* **convert-apply** -- Locates .dfm component instances that match a #convert rule from a conversion-rules file and rewrites all five surfaces: declaration retype, uses-add. [More](convert-apply)
* **convert-reemit** (internal) -- The DFM re-emit stage of the conversion pipeline, driven by convert-apply and by test runners. [More](Maintenance)
* **convert-scaffold** -- Auto-generates a valid conversion-rules file from the real property trees of a from-type and a to-type. [More](convert-scaffold)
* **convert-validate** -- Parses and validates a conversion-rules file (a reFind-superset DSL), checking its #link/#default paths against the real property trees. [More](convert-validate)
* **ConvRulesEditor** -- Visual rulebook editor for the component-conversion rules. [More](Features)
* **glyph-vacuum** -- Measure every streamed glyph or picture under a tree before writing a glyph rule. [More](Features)
* **proptree** -- Recursive deep-property enumerator for a class: flattens its own and inherited properties into dotted paths, recursing into class-typed properties. [More](proptree)

## Graphs and reports

* **butterfly** -- Composes a symbol's callers (upward wing) and callees (downward wing) into one combined chart in a single command. [More](butterfly)
* **Call Graph (Butterfly)** -- Shows callers and callees of one symbol together in a single "butterfly" view. [More](Call-Graph-Butterfly)
* **callgraph** -- Prints an N-deep resolved call tree for a symbol, in either direction. [More](callgraph)
* **Circular Dependency Report (worked example)** -- A worked example: a real four-unit uses cycle, and the report drag-lint produces for it. [More](Circular-Dependency-Report)
* **Circular Uses Report (cycles + fix plan)** -- Finds uses cycles among indexed units and, on request, proposes a followable refactoring plan to break them. [More](Circular-Uses-Report-cycles-fix-plan)
* **deps-report** -- Produces a third-party dependency rollup from an index: which external units/libraries an indexed codebase depends on. [More](deps-report)
* **Export Enums (Delphi const)** -- Uses export enums with --format delphi-const to dump indexed enum types as Delphi const declarations. [More](Export-Enums-Delphi-const)
* **Export Graph (DOT)** -- Uses graph to export the indexed call/reference graph in DOT format, either whole or rooted at a name substring. [More](Export-Graph-DOT)
* **Export to Obsidian** -- Uses export obsidian to write the indexed project out as a set of Obsidian vault markdown pages. [More](Export-to-Obsidian)
* **Find Dead Code** -- Scans the index for code with no references -- candidates to delete. [More](Find-Dead-Code)
* **Forms for testers (CSV)** -- Produces a spreadsheet-style CSV of a project's forms, one row per form, telling a human tester how to reach each form from the main form: the menu, ribbon. [More](Generate-Test-Helper-CSV)
* **Impact / Blast Radius (symbol)** -- Reports what would be affected if a chosen symbol changes -- the set of code to retest. [More](Impact-Blast-Radius-symbol)
* **Reverse Call Tree (clickable, Messages window)** -- The same reverse call tree, rendered into the IDE's Messages window so each line navigates to the caller. [More](Reverse-Call-Tree-clickable-Messages-window)
* **Reverse Call Tree (who calls this, N-deep)** -- Builds the tree of callers of a chosen symbol, transitively, to a chosen depth. [More](Reverse-Call-Tree-who-calls-this-N-deep)
* **Scan TODOs / FIXMEs** -- Scans source for TODO/FIXME/HACK/XXX/REVIEW/NOTE markers. [More](Scan-TODOs-FIXMEs)
* **Show in Call Graph** -- Opens the call graph rooted at the symbol represented by a Structure-tree node. [More](Show-in-Call-Graph)
* **Show Wiring (Spring4D DI + DFM events)** -- Surfaces bindings the compiler does not make obvious: Spring4D container registrations and DFM event hookups for a type. [More](Show-Wiring-Spring4D-DI-DFM-events)
* **Top Symbols (fan-in)** -- Ranks indexed symbols by fan-in -- how many places reference them. [More](Top-Symbols-fan-in)
* **Uses Report (CSV)** -- Exports the project's unit-dependency data as a CSV file. [More](Uses-Report-CSV)

## Diagrams and charts

* **ask (engine verb)** (planned) -- Ask the index a question, get a chart back. [More](Diagrams-and-Charts)
* **Chart questions** -- 25 questions. Every chart question of the Reports submenu and Ask-Report.ps1, imported from REPORT_QUESTIONS. [More](Diagrams-and-Charts)
* **Charts and the IDE** -- Ask a chart question, open the answer, read a round-trip trace, jump to RAD Studio. [More](Charts-and-the-IDE)

## Compiler integration

* **Add Missing Units to uses (whole unit)** -- The whole-unit form of the undeclared-identifier quick-fix: resolves every unresolved name in a unit at once and adds the units that declare them. [More](Add-Missing-Units-to-uses-whole-unit)
* **Compile & Diagnose** -- Compiles a project or unit and folds the compiler's errors and warnings into drag-lint findings. [More](Compile-Diagnose)
* **Compile Buffer (unsaved)** -- Compiles a project with the current editor buffer's unsaved content substituted for its file on disk, then restores the original file unchanged. [More](Compile-Buffer-unsaved)
* **Compile Dependents** -- Check the units that depend on the one being edited now, instead of waiting for the automatic quiet-period pass (lint-tree tier 3). [More](Features)
* **compile-check** -- Runs a compiler-backed check against a single Delphi project (.dproj) or source file (.pas) and reports the result. [More](compile-check)
* **Full Compile Sweep** -- Recompiles a project's stale units and refreshes its stored compiler findings, forcing a full build rather than the default stale-count threshold. [More](Full-Compile-Sweep)
* **ghost-check** -- Compiles a project with one or more units' content temporarily replaced by their unsaved editor buffers, then restores the original files unchanged. [More](ghost-check)
* **ghost-recover** -- Scans a project's hidden D-RAG folder for recovery journals left behind when a ghost-check overlay was interrupted by a crash. [More](ghost-recover)
* **Import Build Log** -- Parses an external dcc or msbuild build log and folds its errors and warnings into drag-lint's stored findings. [More](Import-Build-Log)
* **preprocess-file** -- Diagnostic that prints a file's {$IFDEF}-resolved source to stdout under a given define set. [More](preprocess-file)
* **project-facts** -- Report what the build does: defines that are on and what sets each, imports, output paths and packages. [More](Features)
* **Recover Buffer-Compile Files** -- Restores any file left holding unsaved-buffer content after a Compile Buffer (unsaved) run was interrupted (for example by a crash). [More](Recover-Buffer-Compile-Files)

## Database and Firebird

* **fb-snapshot** -- Connects to a Firebird database and captures a snapshot into a sqlite index. [More](fb-snapshot)
* **link-orm** -- Links a project's code index to a SQL index so ORM-style relationships between Delphi symbols and SQL objects can be resolved across both. [More](link-orm)

## Editor integration

* **drag-lint Graph (dockable)** -- Opens the drag-lint graph viewer as a dockable window inside the IDE, so it can sit beside Structure. [More](drag-lint-Graph-dockable)
* **drag-lint Graph** -- This page documents the "View > Tool Windows > drag-lint Graph" menu entry -- the drag-lint graph viewer. [More](drag-lint-Graph)
* **drag-lint Options** -- The plugin's settings dialog for drag-lint: lets you browse and toggle the lint rule catalog. [More](drag-lint-Options)
* **drag-lint Panel (dockable)** -- Opens the main drag-lint dockable tool window inside the IDE. [More](drag-lint-Panel-dockable)
* **drag-lint** -- This page documents the "View > Tool Windows > drag-lint" menu entry -- the main drag-lint dockable tool window. [More](drag-lint)
* **IDE Menu Reference** -- What every item in the drag-lint menu does. [More](IDE-Menu-Reference)
* **ide-release** -- Asks a running drag-lint Delphi IDE plugin not to respawn its drag-lint.exe child processes for a while -- and to drop the running one on its next request. [More](ide-release)
* **Installation** -- Getting the CLI, the IDE plugin, or the LSP running. [More](Installation)
* **lsp** -- Starts the LSP (Language Server Protocol) stdio server. [More](lsp)
* **serve** -- Starts the MCP (Model Context Protocol) stdio server, for AI clients such as Claude or Cursor to query a drag-lint index. [More](serve)
* **workspace add** -- Registers a project file into a .drag-lint-workspace.json workspace config, so multi-project workspace commands know about it. [More](workspace-add)
* **workspace index** -- Indexes every project registered in a .drag-lint-workspace.json workspace config in one pass. [More](workspace-index)
* **workspace status** -- Reports the status of every project registered in a .drag-lint-workspace.json workspace config. [More](workspace-status)

## Maintenance and diagnostics

* **About and Status** -- The plugin's status window -- versions, connection health, and which indexes are actually in use. [More](About-and-Status)
* **ambiguous-calls** -- Resolver-coverage diagnostic that reports call sites the engine could not pin to exactly one target -- unresolved or ambiguous calls. [More](ambiguous-calls)
* **bench-context** -- Benchmarks the context command by building context bundles for a sample of symbols against a database. [More](bench-context)
* **contrast-selftest** (internal) -- Self-test for the hover contrast computation, driven by a test runner. [More](Maintenance)
* **diff** -- Compares two index databases and reports what changed between them -- for example an index snapshot taken before and after a refactor. [More](diff)
* **doc-facts-selftest** (internal) -- Self-test for the doc-facts renderer, driven by test runners. [More](Maintenance)
* **dump-call-edges** -- Diagnostic that dumps every resolved call edge in the index as refid|targetqname|confidence rows. [More](dump-call-edges)
* **dump-pp-eval** (internal) -- Diagnostic dump of preprocessor expression evaluation, paired with dump-pp-lex. [More](Maintenance)
* **dump-pp-lex** (internal) -- Diagnostic dump of the preprocessor lexer; the documented preprocessor verbs are preprocess-file and pp-profile. [More](Maintenance)
* **dump-refs** -- Diagnostic that dumps every ref in a file together with its enclosingsymbolid attribution. [More](dump-refs)
* **Feature registry** -- The machine-checked master list of every feature, and the generator of the index pages. Register a feature with tools\feature-registry.ps1 add, regenerate the pages with tools\build-feature-pages.ps1, and let the battery guard name what is missing. Needs PowerShell 7.3 and a repository clone. [More](Feature-Registry)
  aliases: blast radius, feature list, quick help, registry
* **info** -- Prints engine self-info: version, build date, license (MIT), tree-sitter details, and capabilities. [More](info)
* **Library Drift Check** -- Flags registered library roots that have source on disk but nothing in the index. [More](Library-Drift-Check)
* **Maintenance** -- Indexes, the manifest, reindexing, and what to do when something looks wrong. [More](Maintenance)
* **Open Plugin Log** -- Opens the drag-lint plugin's own log file. [More](Open-Plugin-Log)
* **resolve-uses** (internal) -- The diagnostic behind check-unit --resolve-uses; not a verb of its own. [More](Maintenance)
* **selftest** (internal) -- Umbrella self-test dispatcher (manifest-merge, glob, closure, dbselect, drift) used by the test battery, not a user verb. [More](Maintenance)
* **shutdown** -- Ask running lsp engines to close their indexes and stand down, so an index can be rebuilt without killing them. [More](Features)
* **sql** -- Runs one read-only SQL statement against an index database and prints the result set. [More](sql)
* **test-store-freshness** (internal) -- Store-freshness probe used by a test runner; it needs --db and does nothing else. [More](Maintenance)

## Declared, not harvested

The guard verifies CLI verbs, menu captions, MCP tools, scripts and pages. The surfaces below are declared by their entries and exercised only by the periodic review; a green battery does not prove them.

* Allow this message: host 'Structure form' (the caption is verified, the host is declared)
* Charts and the IDE: procedure docs\wiki\Charts-and-the-IDE.md
* Circular Dependency Report (worked example): procedure docs\wiki\Circular-Dependency-Report.md
* Copy All Diagnostics: host 'Structure form' (the caption is verified, the host is declared)
* Create helper class: host 'Structure form' (the caption is verified, the host is declared)
* Document it: host 'Structure form' (the caption is verified, the host is declared)
* Document project: host 'Structure form' (the caption is verified, the host is declared)
* Document unit: host 'Structure form' (the caption is verified, the host is declared)
* Effect Summary Legend: procedure docs\wiki\Effect-Summary-Legend.md
* Feature registry: procedure docs\wiki\Feature-Registry.md
* Find Usages: host 'Structure form' (the caption is verified, the host is declared)
* Fix all in project: host 'Structure form' (the caption is verified, the host is declared)
* Fix all in unit: host 'Structure form' (the caption is verified, the host is declared)
* Fix it: host 'Structure form' (the caption is verified, the host is declared)
* Go to Declaration: host 'Structure form' (the caption is verified, the host is declared)
* Go to Implementation: host 'Structure form' (the caption is verified, the host is declared)
* IDE Menu Reference: procedure docs\wiki\IDE-Menu-Reference.md
* Installation: procedure docs\wiki\Installation.md
* Maintenance: procedure docs\wiki\Maintenance.md
* Show in Call Graph: host 'Structure form' (the caption is verified, the host is declared)
* dl:wiki concept blocks: procedure docs\wiki\Wiki-Blocks-Authoring.md
* drag-lint: Project Rules: host 'Project Manager' (the caption is verified, the host is declared)

*Generated by `tools\build-feature-pages.ps1` from `features\`; do not edit by hand.*
