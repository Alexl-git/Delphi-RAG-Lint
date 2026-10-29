# Features

Everything drag-lint does, grouped. Counts on this page were taken from the
running build (`drag-lint rules --json`), not written by hand.

Three surfaces expose these: the **CLI** (`drag-lint <verb>`), the **RAD Studio
plugin** (see [IDE Menu Reference](IDE-Menu-Reference)), and the **language
server** (`drag-lint lsp`).

Inside the plugin, not everything lives on the main menu. **Auto-fix and
"allow this finding" are reachable only by right-clicking a node in the
Structure form** -- see [Fix it](Fix-it), [Fix all in unit](Fix-all-in-unit),
[Fix all in project](Fix-all-in-project) and
[Allow this message](Allow-this-message). There is also a Project Manager
right-click item, [drag-lint: Project Rules...](drag-lint-Project-Rules).

## Notes carried over from the hand-written page

These were prose on the hand-written Features page and have no registry field. Each belongs on the page that owns its topic; move it there and delete it here.

### Linting

**Newest -- the coupling rules.** `global-only-uses-edge` (a global variable is
the only reason unit A depends on unit B, so relocating it deletes the `uses`
edge), `uses-global-census` (how heavy that edge is), `duplicate-global-decl`
(the same interface-level name in two units, so `uses` order decides which one
compiles), `with-hides-outer-symbol` and `stat-gated-destructive`. The first
three are `project-wide` and therefore only reachable through `lint-all` --
`lint <path>` is a genuine subset and never runs them.

Formatting: drag-lint drives **YADF** (the Delphi formatter) for the current
unit or the whole active project, straight from the IDE menu -- see
[Format with YADF](Format-with-YADF) and
[Format Whole Project with YADF](Format-Whole-Project-with-YADF).
**Formatting does not invalidate suppressions.** A `dl:ok` hash is computed over
a normalised line -- whitespace stripped, identifiers lowercased -- so
reindenting and re-spacing cannot change it. Verified on a real file: 10 markers
in, 10 markers out, whitespace the only difference.

Suppression:

* `// drag-lint:ignore [rule-id ...]` -- silence a line.
* `// dl:ok <rule-id>@<hash> -- reason` -- a **reviewed marker**: it carries a
  hash of the line's code tokens and **re-reports itself if the code changes**,
  so a review cannot outlive the code it reviewed. Reindentation and case
  changes do not invalidate it.
* `REVIEWED <yyyy-mm-dd>` anywhere in a marker's reason records when a human last
  re-read it (`-- REVIEWED 2026-09-23 the loop is bounded`). It is a comment, so it
  never changes the hash. `review-marker-reason-unreviewed` (OFF by default)
  reports a missing, invalid, future or too-old stamp (`max_age_days`, default 180).
* `review-marker-placeholder-hash` (ON) reports a marker whose `@hash` was never
  computed (`@0000`, `@xxxx`), including an `@0000` one written in a block
  comment, where no marker is read -- it suppresses nothing.

### Diagrams and charts

Ask a formal question about one symbol and get a clickable chart back. In RAD
Studio, put the caret on the symbol and pick the question from **drag-lint >
Reports**; the chart opens in the browser and the text answer is copied as a
DocInsight `/// <remarks>` block that Auto Document leaves alone. Outside the IDE,
`charts\src\Ask-Report.ps1` asks the same questions. Twenty-five questions: `round-trip`, `butterfly`,
`who-calls`, `what-it-calls`, `who-writes`, `who-reads`, `change-impact`,
`tested-by`, `effects`, `touches-tables`, `class-surface`, `hierarchy`, `deps`,
`cycles`, `wiring`, `lifecycle`, `event-wiring`, `architecture`,
`protocol-trace`, `crosses-boundary`, `shown-where`, `exception-paths`,
`consumers`, `feeds-from` and `lands-where`. Every row in a chart is a fact with a file and a line, and links
back to it.

---

## Indexing

Build and maintain the per-project and library indexes.

| Feature | Surfaces | Status |
|---|---|---|
| [Auto-Document Whole Project](Auto-Document-Whole-Project) | drag-lint > Generate & Export > Auto-Document Whole Project...; `index`; `document` |  |
| [Include-file indexing and IF evaluation](inc-indexing) | `index` |  |
| [Index a project against its active build config](index-build-config) | `index` |  |
| [migrate-dbs](migrate-dbs) | `migrate-dbs`; drag-lint > Index & Maintenance > Migrate Index DBs to _D-RAG... |  |
| [pp-profile](pp-profile) | `pp-profile` |  |
| [purge-locals](purge-locals) | `purge-locals`; drag-lint > Index & Maintenance > Shrink Index (purge locals)... |  |
| [Rebuild Index for This Project](Rebuild-Index-for-This-Project) | drag-lint > Index & Maintenance > Rebuild Index for This Project; `index` |  |
| [register-project](Features) | `register-project` |  |
| [schema](schema) | `schema` |  |
| [Show Resolved DBs (debug)](Show-Resolved-DBs-debug) | drag-lint > Index & Maintenance > Show Resolved DBs (debug)...; `resolve-dbs` |  |

## Search and navigation

Find symbols, callers, callees, text and types in the index.

| Feature | Surfaces | Status |
|---|---|---|
| [call-path](call-path) | `call-path`; drag-lint > Uses & Dependencies > Call Path Between Two Routines... |  |
| [Class Surface](Class-Surface) | drag-lint > Inspect Symbol > Class Surface...; `surface` |  |
| [Compiler Hints](Compiler-Hints) | drag-lint > Code Quality > Compiler Hints...; `query hints` |  |
| [context](context) | `context` |  |
| [Find Undocumented (public)](Find-Undocumented-public) | drag-lint > Code Quality > Find Undocumented (public)...; `query find` |  |
| [Find Usages](Find-Usages) | drag-lint > Find Usages... |  |
| [Find Usages](Find-Usages-context) | Structure form: Find Usages; `usages` |  |
| [find-callees](find-callees) | `find-callees`; drag-lint > Uses & Dependencies > What This Routine Calls (callees)... |  |
| [find-unit](find-unit) | `find-unit`; drag-lint > Uses & Dependencies > Find Unit for Symbol (add to uses)... |  |
| [Gain (counted savings)](Gain-usage-log) | `gain` |  |
| [Go to Declaration](Go-to-Declaration) | Structure form: Go to Declaration |  |
| [Go to Definition](Go-to-Definition) | drag-lint > Go to Definition |  |
| [Go to Implementation](Go-to-Implementation) | Structure form: Go to Implementation |  |
| [helpers-of](helpers-of) | `helpers-of`; drag-lint > Inspect Symbol > Helpers of Type... |  |
| [Hover at Cursor](Hover-at-Cursor) | drag-lint > Hover at Cursor; `hover` |  |
| [outline](outline) | `outline`; drag-lint > Show Structure |  |
| [query --concept](concept-search) | `query` |  |
| [query --kind --all](query-kind-all) | `query` |  |
| [query --name-like](query-name-like) | `query` |  |
| [query --text --near](query-text-near) | `query` |  |
| [query ancestors](query-ancestors) | `query ancestors`; drag-lint > Inspect Symbol > Ancestors of Type (full chain)... |  |
| [query descendants](query-descendants) | `query descendants`; drag-lint > Inspect Symbol > Descendants of Class... |  |
| [query find-callers](query-find-callers) | `query find-callers`; drag-lint > Find Usages... |  |
| [query type-usage](query-type-usage) | `query type-usage` |  |
| [query typecat](query-typecat) | `query typecat` |  |
| [query unit-usage](query-unit-usage) | `query unit-usage` |  |
| [Show Completion](Show-Completion) | drag-lint > Show Completion |  |
| [Show Signature Help](Show-Signature-Help) | drag-lint > Show Signature Help |  |
| [Show Structure](Show-Structure) | drag-lint > Show Structure |  |
| [Symbol Search](Symbol-Search) | drag-lint > Symbol Search...; `query` |  |
| [Symbol Slice](Symbol-Slice) | drag-lint > Inspect Symbol > Symbol Slice...; `slice` |  |
| [Type at Cursor](Type-at-Cursor) | drag-lint > Inspect Symbol > Type at Cursor; `typeat` |  |
| [usages](usages) | `usages`; drag-lint > Find Usages... |  |
| [wiki](wiki) | `wiki` |  |

## Linting

Rules, autofix, suppression markers and project-wide checks.

**290 rules. 111 have an auto-fix. 246 are on by default.** 197 are built-in checks; 93 are external tree-sitter `.scm` rules you can read and extend in `rules\`. Run `drag-lint rules` for the always-current catalogue.

| Category | Rules | With auto-fix |
|---|---:|---:|
| bug-patterns | 88 | 33 |
| complexity | 13 | 2 |
| data-flow | 9 | 2 |
| dead-code | 19 | 15 |
| documentation | 5 | 4 |
| firedac | 3 | 3 |
| metrics | 8 | - |
| modernize | 4 | 4 |
| naming | 13 | 9 |
| other | 11 | 3 |
| platform | 10 | 4 |
| policy | 3 | - |
| project-wide | 30 | 6 |
| refactoring | 20 | 8 |
| resource-lifetime | 14 | 7 |
| review-markers | 5 | 2 |
| security | 22 | 2 |
| structure | 13 | 7 |
| **Total** | **290** | **111** |

| Feature | Surfaces | Status |
|---|---|---|
| [Autofix for fixable rules](autofix-wave) | `lint` |  |
| [Compliance labels (CWE, CERT, MISRA)](compliance-labels) | `rules`; `lint-all` |  |
| [Copy All Diagnostics](Copy-All-Diagnostics) | Structure form: Copy All Diagnostics; `lint` |  |
| [Copy Diagnostics (Current File)](Copy-Diagnostics-Current-File) | About window: Copy Diagnostics (Current File); `lint` |  |
| [Copy Selected Diagnostics](Copy-Selected-Diagnostics) | Structure form: Copy |  |
| [Downgrade fixes (compat rules)](compat-downgrade-fixes) | `lint` | planned |
| [drag-lint: Project Rules](drag-lint-Project-Rules) | Project Manager: drag-lint: Project Rules; `rules` |  |
| [exceptions-sync](Features) | `exceptions-sync` |  |
| [Fix all in project](Fix-all-in-project) | Structure form: Fix all in project; `lint-all` |  |
| [Fix all in unit](Fix-all-in-unit) | Structure form: Fix all in unit; `lint` |  |
| [Fix all reliability (1.31.3)](Fix-all-reliability) | Structure form: Fix all in unit; `lint` |  |
| [Fix it](Fix-it) | Structure form: Fix it; `lint`; `uses-fix` |  |
| [Format Whole Project with YADF](Format-Whole-Project-with-YADF) | drag-lint > Format Whole Project with YADF...; `format`; `index` |  |
| [Format with YADF](Format-with-YADF) | drag-lint > Format with YADF; `format` |  |
| [Gap-wave lint rules](gap-wave-rules) | `rules` |  |
| [Lint Buffer (Unsaved)](Lint-Buffer-Unsaved) | About window: Lint Buffer (Unsaved); `lint` |  |
| [Lint rules](rules) | 290 rules, 111 fixable; `rules` |  |
| [lint-project](lint-project) | `lint-project`; drag-lint > Code Quality > Project Structure Rules (god-class, layering...)... |  |
| [lint-tree](lint-tree) | `lint-tree` |  |
| [Rename across every project that compiles a shared unit](Multi-Project-Rename) | `lint`; Structure form: Fix it; Structure form: Fix all in unit |  |
| [Rescan this unit](Rescan-this-unit) | Structure form: Rescan this unit; `index` |  |
| [Run AST Checks](Run-AST-Checks) | About window: Run AST Checks; `check-ast` |  |
| [Run Diagnostics (didSave)](Run-Diagnostics-didSave) | About window: Run Diagnostics (didSave) |  |
| [Run Lint All (Full Report)](Run-Lint-All-Full-Report) | drag-lint > Code Quality > Run Lint All (Full Report)...; `lint-all` |  |
| [Taint analysis (SQL, command, path)](taint-analysis) | `lint-all` |  |
| [Target compiler (--target-compiler)](target-compiler) | `lint`; `lint-all`; `rules`; drag-lint > Code Quality > Run Lint All (Full Report)... |  |
| [Type-level dl:ok review](Type-Level-Review-Marker) | procedure: `docs\wiki\Type-Level-Review-Marker.md` |  |
| [type-name-prefix: expected letter from the ancestor chain](Type-Name-Prefix-Origin) | `lint`; `lint-all`; `lint` |  |

## Documentation

DocInsight comments generated from the index, and drift detection.

| Feature | Surfaces | Status |
|---|---|---|
| [dl:wiki concept blocks](Wiki-Blocks-Authoring) | `wiki`; procedure: `docs\wiki\Wiki-Blocks-Authoring.md` |  |
| [Doc Comment Stub (symbol)](Doc-Comment-Stub-symbol) | drag-lint > Generate & Export > Doc Comment Stub (symbol)...; `generate-docs` |  |
| [doc-drift](doc-drift) | `doc-drift` |  |
| [doc-forget](Features) | `doc-forget`; drag-lint > Generate & Export > Forget Documentation Project Tag...; drag-lint > Generate & Export > List Documentation Project Tags |  |
| [Document it](Document-it) | Structure form: Document it; `document` |  |
| [Document project](Document-project) | Structure form: Document project; `document` |  |
| [Document unit](Document-unit) | Structure form: Document unit; `document` |  |
| [document-all](document-all) | `document-all`; drag-lint > Generate & Export > Auto-Document Every Indexed Unit... |  |
| [Effect Summary Legend](Effect-Summary-Legend) | procedure: `docs\wiki\Effect-Summary-Legend.md`; drag-lint > Help > Effect Summary Legend |  |
| [shared-unit](shared-unit) | `shared-unit` |  |

## Refactoring and code generation

Rename, extract, safe delete, uses cleanup and code stubs.

| Feature | Surfaces | Status |
|---|---|---|
| [Allow this message](Allow-this-message) | Structure form: Allow this message; `allow` |  |
| [allow](allow) | `allow` |  |
| [Create helper class](Create-helper-class) | Structure form: Create helper class; `create-enum-helper` |  |
| [create-enum-helper](create-enum-helper) | `create-enum-helper`; drag-lint > Generate & Export > Enum Record Helper (symbol)... |  |
| [extract-method](extract-method) | `extract-method`; drag-lint > Extract Method (selection)... (Ctrl+Alt+M) |  |
| [Quick-Fix: Add Unit for Inline Hint (H2443) at Cursor](Quick-Fix-Add-Unit-for-Inline-Hint-H2443-at-Cursor) | drag-lint > Uses & Dependencies > Quick-Fix: Add Unit for Inline Hint (H2443) at Cursor |  |
| [Quick-Fix: Add Unit for Undeclared at Cursor (Ctrl+Alt+U)](Quick-Fix-Add-Unit-for-Undeclared-at-Cursor-Ctrl-Alt-U) | drag-lint > Uses & Dependencies > Quick-Fix: Add Unit for Undeclared at Cursor (Ctrl+Alt+U) |  |
| [Quick-Fix: Convert Public Field to Property at Cursor](Quick-Fix-Convert-Public-Field-to-Property-at-Cursor) | drag-lint > Convert Public Field to Property at Cursor |  |
| [Reconcile Project Members (.dpr/.dproj)](Reconcile-Project-Members-dpr-dproj) | drag-lint > Uses & Dependencies > Reconcile Project Members (.dpr/.dproj)...; `reconcile-project` |  |
| [Rename Symbol](Rename-Symbol) | drag-lint > Rename Symbol...; `rename` |  |
| [safe-delete](safe-delete) | `safe-delete`; drag-lint > Safe Delete Symbol... |  |
| [Unit Test Stub (symbol)](Unit-Test-Stub-symbol) | drag-lint > Generate & Export > Unit Test Stub (symbol)...; `generate-test` |  |
| [Uses & Deps Tab](Features) | drag-lint > Uses & Dependencies > Uses & Deps Tab -- review & apply fixes... |  |
| [Uses Audit -- interface->impl moves + unused (this unit)](Uses-Audit-interface-impl-moves-unused-this-unit) | drag-lint > Uses & Dependencies > Uses Audit -- interface->impl moves + unused...; `uses-audit` |  |
| [Uses Cleanup Preview (compiler-verified, this unit)](Uses-Cleanup-Preview-compiler-verified-this-unit) | drag-lint > Uses & Dependencies > Uses Cleanup Preview (compiler-verified)...; `uses-fix` |  |

## Component conversion

Rule-driven migration of legacy component types.

| Feature | Surfaces | Status |
|---|---|---|
| [Convert progress](convrules-editor-convert-progress) | `ConvRulesEditor.exe` (Convert tab progress line) |  |
| [convert-apply #migrate (member, type and enum rename / DL_NONE)](convert-apply-migrate) | `convert-apply` |  |
| [convert-apply](convert-apply) | `convert-apply` |  |
| [convert-reemit](Maintenance) | `convert-reemit` | internal |
| [convert-scaffold](convert-scaffold) | `convert-scaffold` |  |
| [convert-validate](convert-validate) | `convert-validate` |  |
| [ConvRulesEditor](convrules-editor) | `ConvRulesEditor.exe`; `ConvRulesEditor.exe` (Conversion > Convert... (the IDE plugin starts it with --convert-request FILE and probes --write-capabilities FILE)) |  |
| [Curate rule books](convrules-editor-curate) | `ConvRulesEditor.exe` (File > Curate...) |  |
| [glyph-vacuum](glyph-vacuum) | `glyph-vacuum` |  |
| [Member migration (#migrate)](convrules-editor-migrate) | `ConvRulesEditor.exe` (Work list tab > Migrate...); `ConvRulesEditor.exe` (Classes tab > Members list > Add...) |  |
| [Progress window and busy guard](convrules-editor-busy-guard) | `ConvRulesEditor.exe` (Progress window (appears by itself)) |  |
| [proptree](proptree) | `proptree` |  |
| [Qualify #convert quick fix](convrules-editor-qualify-fix) | `ConvRulesEditor.exe` (Convert tab > Qualify #convert...); `ConvRulesEditor.exe` (Convert tab > Qualify all...) |  |
| [Reindex project](convrules-editor-reindex-project) | `ConvRulesEditor.exe` (Conversion > Reindex project) |  |
| [Rule book and source encoding](convrules-editor-encoding) | `ConvRulesEditor.exe` (File > Encoding); `ConvRulesEditor.exe` (File > Save); `ConvRulesEditor.exe` (Convert tab > Convert) |  |
| [Rule chains (single-pass warning, merge / split)](convrules-editor-rule-chains) | `ConvRulesEditor.exe` (Conversion > Rule chains...); `ConvRulesEditor.exe` (File > Save (offer)) |  |
| [Work list](convrules-editor-work-list) | `ConvRulesEditor.exe` (View > Work list) |  |

## Graphs and reports

Call graphs, dependency reports, dead code, tester spreadsheets.

| Feature | Surfaces | Status |
|---|---|---|
| [butterfly](butterfly) | `butterfly`; drag-lint > Uses & Dependencies > Call Graph (Butterfly)... |  |
| [Call Graph (Butterfly)](Call-Graph-Butterfly) | drag-lint > Uses & Dependencies > Call Graph (Butterfly)...; `reverse-calltree` |  |
| [callgraph](callgraph) | `callgraph`; drag-lint > Uses & Dependencies > Call Tree (callers or callees, N-deep)... |  |
| [Circular Dependency Report (worked example)](Circular-Dependency-Report) | procedure: `docs\wiki\Circular-Dependency-Report.md`; drag-lint > Uses & Dependencies > Circular Uses Report (cycles + fix plan)... |  |
| [Circular Uses Report (cycles + fix plan)](Circular-Uses-Report-cycles-fix-plan) | drag-lint > Uses & Dependencies > Circular Uses Report (cycles + fix plan)...; `cycles` |  |
| [Code-built menu tree and registry drift](Menu-Tree) | `menu-tree`; `menu-drift` |  |
| [Cycles fix (mechanical, compile-gated)](Circular-Uses-Report-cycles-fix-plan) | `cycles`; drag-lint > Uses & Dependencies > Fix Circular Uses Mechanically (dry run)...; View > Tool Windows > drag-lint > Uses & Deps > This project -- Circular uses (cycles --fix); Structure form: Fix this cycle (dry run)...; Structure form: Apply cycle fix...; `charts\src\Emit-Cycles.ps1` |  |
| [deps-report](deps-report) | `deps-report`; drag-lint > Uses & Dependencies > Dependency Report (third-party rollup)... |  |
| [Export Enums (Delphi const)](Export-Enums-Delphi-const) | drag-lint > Generate & Export > Export Enums (Delphi const)...; `export enums` |  |
| [Export Graph (DOT)](Export-Graph-DOT) | drag-lint > Generate & Export > Export Graph (DOT)...; `graph` |  |
| [Export to Obsidian](Export-to-Obsidian) | drag-lint > Generate & Export > Export to Obsidian...; `export obsidian` |  |
| [Find Dead Code](Find-Dead-Code) | drag-lint > Code Quality > Find Dead Code...; `find-deadcode` |  |
| [Forms for testers (CSV)](Generate-Test-Helper-CSV) | drag-lint > Reports > Forms for testers (CSV)...; `forms-csv` |  |
| [Impact / Blast Radius (symbol)](Impact-Blast-Radius-symbol) | drag-lint > Uses & Dependencies > Impact / Blast Radius (symbol)...; `impact` |  |
| [Overview (first-turn summary)](Overview-first-turn) | `overview` |  |
| [Reverse Call Tree (clickable, Messages window)](Reverse-Call-Tree-clickable-Messages-window) | `reverse-calltree`; drag-lint > Uses & Dependencies > Reverse Call Tree (who calls this, N-deep)... |  |
| [Reverse Call Tree (who calls this, N-deep)](Reverse-Call-Tree-who-calls-this-N-deep) | drag-lint > Uses & Dependencies > Reverse Call Tree (who calls this, N-deep)...; `reverse-calltree` |  |
| [Scan TODOs / FIXMEs](Scan-TODOs-FIXMEs) | drag-lint > Code Quality > Scan TODOs / FIXMEs...; `todos` |  |
| [Show in Call Graph](Show-in-Call-Graph) | Structure form: Show in Call Graph; `reverse-calltree` |  |
| [Show Wiring (Spring4D DI + DFM events)](Show-Wiring-Spring4D-DI-DFM-events) | drag-lint > Uses & Dependencies > Show Wiring (Spring4D DI + DFM events)...; `wiring` |  |
| [Top Symbols (fan-in)](Top-Symbols-fan-in) | drag-lint > Code Quality > Top Symbols (fan-in)...; `top` |  |
| [Uses Report (CSV)](Uses-Report-CSV) | drag-lint > Uses & Dependencies > Uses Report (CSV)...; `uses-report` |  |

## Diagrams and charts

Ask a question about a symbol and get a clickable chart.

| Feature | Surfaces | Status |
|---|---|---|
| [ask](ask) | `ask`; drag-lint > Reports |  |
| [Chart questions](Diagrams-and-Charts) | 26 questions; `ask`; drag-lint > Reports |  |
| [Charts and the IDE](Charts-and-the-IDE) | procedure: `docs\wiki\Charts-and-the-IDE.md`; drag-lint > Reports |  |
| [Click-to-source: the draglint:// handler](Draglint-Protocol-Handler) | `protocol`; `drag-lint-open.exe` |  |
| [Compare a report with current code](compare) | `compare`; drag-lint > Reports > Compare a Saved Report or Chart with Current Code... |  |
| [Where the charts find Graphviz](Chart-Graphviz-Lookup) | procedure: `docs\wiki\Chart-Graphviz-Lookup.md` |  |

## Compiler integration

Compile, fold compiler output into findings, preprocess.

| Feature | Surfaces | Status |
|---|---|---|
| [Add Missing Units to uses (whole unit)](Add-Missing-Units-to-uses-whole-unit) | drag-lint > Uses & Dependencies > Add Missing Units to uses (whole unit)...; `check-unit` |  |
| [Compile & Diagnose](Compile-Diagnose) | drag-lint > Compile & Diagnose |  |
| [Compile Buffer (unsaved)](Compile-Buffer-unsaved) | drag-lint > Compile Buffer (unsaved) |  |
| [Compile Dependents](Features) | drag-lint > Compile Dependents |  |
| [compile-check](compile-check) | `compile-check` |  |
| [Full Compile Sweep](Full-Compile-Sweep) | drag-lint > Full Compile Sweep; `refresh-findings` |  |
| [ghost-check](ghost-check) | `ghost-check`; drag-lint > Compile Buffer (unsaved) |  |
| [ghost-recover](ghost-recover) | `ghost-recover`; About window: Recover Buffer-Compile Files |  |
| [Import Build Log](Import-Build-Log) | About window: Import Build Log...; `import-log` |  |
| [preprocess-file](preprocess-file) | `preprocess-file` |  |
| [project-facts](Features) | `project-facts` |  |
| [Recover Buffer-Compile Files](Recover-Buffer-Compile-Files) | About window: Recover Buffer-Compile Files |  |

## Database and Firebird

SQL scripts, live schema snapshots, ORM links.

| Feature | Surfaces | Status |
|---|---|---|
| [fb-snapshot](fb-snapshot) | `fb-snapshot` |  |
| [link-orm](link-orm) | `link-orm` |  |

## Editor integration

The RAD Studio plugin, the language server, MCP and workspaces.

| Feature | Surfaces | Status |
|---|---|---|
| [drag-lint Graph (dockable)](drag-lint-Graph-dockable) | drag-lint > drag-lint Graph (dockable) |  |
| [drag-lint Graph](drag-lint-Graph) | View > Tool Windows > drag-lint Graph |  |
| [drag-lint Options](drag-lint-Options) | drag-lint > drag-lint Options... |  |
| [drag-lint Panel (dockable)](drag-lint-Panel-dockable) | drag-lint > drag-lint Panel (dockable) |  |
| [drag-lint](drag-lint) | View > Tool Windows > drag-lint |  |
| [Help line (DL page)](ide-help-line) | View > Tool Windows > drag-lint; drag-lint > Help > Help on a feature...; drag-lint > Help > All features (web) |  |
| [IDE Menu Reference](IDE-Menu-Reference) | procedure: `docs\wiki\IDE-Menu-Reference.md`; drag-lint > Help > IDE Menu Reference |  |
| [ide-release](ide-release) | `ide-release` |  |
| [init: one command from a project to a wired AI client](init-verb) | `init` |  |
| [Installation](Installation) | `drag-lint.exe`; procedure: `docs\wiki\Installation.md` |  |
| [LSP full rule set on save](lsp-proxy-merge) | `lsp` |  |
| [LSP protocol extensions](lsp-proxy-merge) | `lsp textDocument/documentSymbol`; `lsp textDocument/implementation`; `lsp textDocument/declaration`; `lsp textDocument/rename`; `lsp textDocument/codeLens`; `lsp textDocument/semanticTokens/full`; `lsp textDocument/inlayHint`; `lsp workspace/executeCommand`; `lsp draglint/ping` |  |
| [LSP proxy merge](lsp-proxy-merge) | `lsp` |  |
| [lsp](lsp) | `lsp` |  |
| [MCP server](Register-MCP-Server) | `mcp find_symbol`; `mcp find_callers`; `mcp lint`; `mcp get_symbol_doc`; `mcp find_by_doc_tag`; `mcp find_undocumented`; `mcp get_impact`; `mcp get_wiring`; `mcp get_surface`; `mcp get_slice`; `mcp get_context_bundle`; `mcp get_type_at_position`; `mcp rename_symbol`; `mcp run_ast_checks`; `mcp run_compile_check` |  |
| [Output encoding (--output-encoding)](output-encoding) | `sql` |  |
| [project-context](project-context) | `project-context` |  |
| [Register the MCP server (Claude Code, VS Code, Cursor)](Register-MCP-Server) | `mcp-config` |  |
| [serve](serve) | `serve` |  |
| [Setup installer](Setup-Installer) | procedure: `docs\wiki\Setup-Installer.md` | experimental |
| [Switch VS Code Delphi MCP entry](lsp-proxy-merge) | `drag-lint-switch.exe` (drag-lint-switch --vscode --off) |  |
| [VS Code extension: Problems stay current](vscode-extension) | `lsp draglint/refreshDiagnostics`; `lsp workspace/didChangeWatchedFiles` |  |
| [workspace add](workspace-add) | `workspace add` |  |
| [workspace index](workspace-index) | `workspace index` |  |
| [workspace status](workspace-status) | `workspace status` |  |

## Maintenance and diagnostics

Which databases cover what, drift checks, raw dumps, self-tests.

| Feature | Surfaces | Status |
|---|---|---|
| [About and Status](About-and-Status) | drag-lint > About; `info`; About window: Check for Updates; About window: Close; About window: Copy Diagnostics (Current File); About window: Copy Report; About window: Diagnose Current State; About window: Import Build Log...; About window: Lint Buffer (Unsaved); About window: Open Plugin Log; About window: Recover Buffer-Compile Files; About window: Refresh; About window: Run AST Checks; About window: Run Diagnostics (didSave) |  |
| [ambiguous-calls](ambiguous-calls) | `ambiguous-calls` |  |
| [bench-context](bench-context) | `bench-context` |  |
| [contrast-selftest](Maintenance) | `contrast-selftest` | internal |
| [diff](diff) | `diff` |  |
| [doc-facts-selftest](Maintenance) | `doc-facts-selftest` | internal |
| [dump-call-edges](dump-call-edges) | `dump-call-edges` |  |
| [dump-parse-uses](Maintenance) | `dump-parse-uses` | internal |
| [dump-pp-eval](Maintenance) | `dump-pp-eval` | internal |
| [dump-pp-lex](Maintenance) | `dump-pp-lex` | internal |
| [dump-refs](dump-refs) | `dump-refs` |  |
| [Feature registry](Feature-Registry) | `tools\publish-release.ps1 -Version -DryRun`; procedure: `docs\wiki\Feature-Registry.md` |  |
| [featuregen](featuregen) | `featuregen.exe`; `build\_build_featuregen_local.bat builds featuregen.exe from this checkout`; `tools\featuregen-gate.ps1 -Repo -Full`; procedure: `docs\wiki\featuregen.md` | internal |
| [info](info) | `info` |  |
| [Library Drift Check](Library-Drift-Check) | drag-lint > Index & Maintenance > Library Drift Check...; `library-drift` |  |
| [Maintenance](Maintenance) | procedure: `docs\wiki\Maintenance.md` |  |
| [Open Plugin Log](Open-Plugin-Log) | About window: Open Plugin Log |  |
| [resolve-uses](Maintenance) | `resolve-uses` | internal |
| [selftest](Maintenance) | `selftest` | internal |
| [shutdown](Features) | `shutdown` |  |
| [sql](sql) | `sql` |  |
| [test-store-freshness](Maintenance) | `test-store-freshness` | internal |

## Uses and Dependencies

Which units a unit needs, where they go in uses, and the cycles they make

| Feature | Surfaces | Status |
|---|---|---|
| [Missing unit in uses (unit-missing-from-uses)](unit-missing-from-uses) | `lint` |  |

---

*Generated by `featuregen build --all` from `features\`; counts come from `drag-lint rules --json` at generation time. Do not edit by hand.*
