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
| [migrate-dbs](migrate-dbs) | `migrate-dbs` |  |
| [pp-profile](pp-profile) | `pp-profile` |  |
| [purge-locals](purge-locals) | `purge-locals` |  |
| [Rebuild Index for This Project](Rebuild-Index-for-This-Project) | drag-lint > Index & Maintenance > Rebuild Index for This Project; `index` |  |
| [register-project](Features) | `register-project` |  |
| [schema](schema) | `schema` |  |
| [Show Resolved DBs (debug)](Show-Resolved-DBs-debug) | drag-lint > Index & Maintenance > Show Resolved DBs (debug)...; `resolve-dbs` |  |

## Search and navigation

Find symbols, callers, callees, text and types in the index.

| Feature | Surfaces | Status |
|---|---|---|
| [call-path](call-path) | `call-path` |  |
| [Class Surface](Class-Surface) | drag-lint > Inspect Symbol > Class Surface...; `surface` |  |
| [Compiler Hints](Compiler-Hints) | drag-lint > Code Quality > Compiler Hints...; `query hints` |  |
| [context](context) | `context` |  |
| [Find Undocumented (public)](Find-Undocumented-public) | drag-lint > Code Quality > Find Undocumented (public)...; `query find` |  |
| [Find Usages](Find-Usages) | drag-lint > Find Usages... |  |
| [Find Usages](Find-Usages-context) | Structure form: Find Usages; `usages` |  |
| [find-callees](find-callees) | `find-callees` |  |
| [find-unit](find-unit) | `find-unit` |  |
| [Go to Declaration](Go-to-Declaration) | Structure form: Go to Declaration |  |
| [Go to Definition](Go-to-Definition) | drag-lint > Go to Definition |  |
| [Go to Implementation](Go-to-Implementation) | Structure form: Go to Implementation |  |
| [helpers-of](helpers-of) | `helpers-of` |  |
| [Hover at Cursor](Hover-at-Cursor) | drag-lint > Hover at Cursor; `hover` |  |
| [outline](outline) | `outline` |  |
| [query --kind --all](query-kind-all) | `query` |  |
| [query --name-like](query-name-like) | `query` |  |
| [query ancestors](query-ancestors) | `query ancestors` |  |
| [query descendants](query-descendants) | `query descendants` |  |
| [query find-callers](query-find-callers) | `query find-callers` |  |
| [query type-usage](query-type-usage) | `query type-usage` |  |
| [query typecat](query-typecat) | `query typecat` |  |
| [query unit-usage](query-unit-usage) | `query unit-usage` |  |
| [Show Completion](Show-Completion) | drag-lint > Show Completion |  |
| [Show Signature Help](Show-Signature-Help) | drag-lint > Show Signature Help |  |
| [Show Structure](Show-Structure) | drag-lint > Show Structure |  |
| [Symbol Search](Symbol-Search) | drag-lint > Symbol Search...; `query` |  |
| [Symbol Slice](Symbol-Slice) | drag-lint > Inspect Symbol > Symbol Slice...; `slice` |  |
| [Type at Cursor](Type-at-Cursor) | drag-lint > Inspect Symbol > Type at Cursor; `typeat` |  |
| [usages](usages) | `usages` |  |
| [wiki](wiki) | `wiki` |  |

## Linting

Rules, autofix, suppression markers and project-wide checks.

**189 rules. 23 have an auto-fix. 159 are on by default.** 136 are built-in checks; 53 are external tree-sitter `.scm` rules you can read and extend in `rules\`. Run `drag-lint rules` for the always-current catalogue.

| Category | Rules | With auto-fix |
|---|---:|---:|
| bug-patterns | 54 | 6 |
| complexity | 11 | - |
| data-flow | 9 | - |
| dead-code | 12 | 6 |
| documentation | 5 | 2 |
| firedac | 3 | - |
| metrics | 8 | - |
| naming | 10 | 8 |
| other | 6 | - |
| platform | 10 | - |
| project-wide | 20 | - |
| refactoring | 11 | - |
| resource-lifetime | 8 | 1 |
| review-markers | 5 | - |
| security | 10 | - |
| structure | 7 | - |
| **Total** | **189** | **23** |

| Feature | Surfaces | Status |
|---|---|---|
| [Copy All Diagnostics](Copy-All-Diagnostics) | Structure form: Copy All Diagnostics; `lint` |  |
| [Copy Diagnostics (Current File)](Copy-Diagnostics-Current-File) | About window: Copy Diagnostics (Current File); `lint` |  |
| [drag-lint: Project Rules](drag-lint-Project-Rules) | Project Manager: drag-lint: Project Rules; `rules` |  |
| [exceptions-sync](Features) | `exceptions-sync` |  |
| [Fix all in project](Fix-all-in-project) | Structure form: Fix all in project; `lint-all` |  |
| [Fix all in unit](Fix-all-in-unit) | Structure form: Fix all in unit; `lint` |  |
| [Fix it](Fix-it) | Structure form: Fix it; `lint` |  |
| [Format Whole Project with YADF](Format-Whole-Project-with-YADF) | drag-lint > Format Whole Project with YADF...; `format`; `index` |  |
| [Format with YADF](Format-with-YADF) | drag-lint > Format with YADF; `format` |  |
| [Lint Buffer (Unsaved)](Lint-Buffer-Unsaved) | About window: Lint Buffer (Unsaved); `lint` |  |
| [Lint rules](rules) | 189 rules, 23 fixable; `rules` |  |
| [lint-project](lint-project) | `lint-project` |  |
| [lint-tree](lint-tree) | `lint-tree` |  |
| [Run AST Checks](Run-AST-Checks) | About window: Run AST Checks; `check-ast` |  |
| [Run Diagnostics (didSave)](Run-Diagnostics-didSave) | About window: Run Diagnostics (didSave) |  |
| [Run Lint All (Full Report)](Run-Lint-All-Full-Report) | drag-lint > Code Quality > Run Lint All (Full Report)...; `lint-all` |  |

## Documentation

DocInsight comments generated from the index, and drift detection.

| Feature | Surfaces | Status |
|---|---|---|
| [dl:wiki concept blocks](Wiki-Blocks-Authoring) | `wiki`; procedure: `docs\wiki\Wiki-Blocks-Authoring.md` |  |
| [Doc Comment Stub (symbol)](Doc-Comment-Stub-symbol) | drag-lint > Generate & Export > Doc Comment Stub (symbol)...; `generate-docs` |  |
| [doc-drift](doc-drift) | `doc-drift` |  |
| [doc-forget](Features) | `doc-forget` |  |
| [Document it](Document-it) | Structure form: Document it; `document` |  |
| [Document project](Document-project) | Structure form: Document project; `document` |  |
| [Document unit](Document-unit) | Structure form: Document unit; `document` |  |
| [document-all](document-all) | `document-all` |  |
| [Effect Summary Legend](Effect-Summary-Legend) | procedure: `docs\wiki\Effect-Summary-Legend.md` |  |
| [shared-unit](shared-unit) | `shared-unit` |  |

## Refactoring and code generation

Rename, extract, safe delete, uses cleanup and code stubs.

| Feature | Surfaces | Status |
|---|---|---|
| [Allow this message](Allow-this-message) | Structure form: Allow this message; `allow` |  |
| [allow](allow) | `allow` |  |
| [Create helper class](Create-helper-class) | Structure form: Create helper class; `create-enum-helper` |  |
| [create-enum-helper](create-enum-helper) | `create-enum-helper` |  |
| [extract-method](extract-method) | `extract-method` |  |
| [Quick-Fix: Add Unit for Inline Hint (H2443) at Cursor](Quick-Fix-Add-Unit-for-Inline-Hint-H2443-at-Cursor) | drag-lint > Uses & Dependencies > Quick-Fix: Add Unit for Inline Hint (H2443) at Cursor |  |
| [Quick-Fix: Add Unit for Undeclared at Cursor (Ctrl+Alt+U)](Quick-Fix-Add-Unit-for-Undeclared-at-Cursor-Ctrl-Alt-U) | drag-lint > Uses & Dependencies > Quick-Fix: Add Unit for Undeclared at Cursor (Ctrl+Alt+U) |  |
| [Quick-Fix: Convert Public Field to Property at Cursor](Quick-Fix-Convert-Public-Field-to-Property-at-Cursor) | drag-lint > Convert Public Field to Property at Cursor |  |
| [Reconcile Project Members (.dpr/.dproj)](Reconcile-Project-Members-dpr-dproj) | drag-lint > Uses & Dependencies > Reconcile Project Members (.dpr/.dproj)...; `reconcile-project` |  |
| [Rename Symbol](Rename-Symbol) | drag-lint > Rename Symbol...; `rename` |  |
| [safe-delete](safe-delete) | `safe-delete` |  |
| [Unit Test Stub (symbol)](Unit-Test-Stub-symbol) | drag-lint > Generate & Export > Unit Test Stub (symbol)...; `generate-test` |  |
| [Uses & Deps Tab](Features) | drag-lint > Uses & Dependencies > Uses & Deps Tab -- review & apply fixes... |  |
| [Uses Audit -- interface->impl moves + unused (this unit)](Uses-Audit-interface-impl-moves-unused-this-unit) | drag-lint > Uses & Dependencies > Uses Audit -- interface->impl moves + unused (this unit)...; `uses-audit` |  |
| [Uses Cleanup Preview (compiler-verified, this unit)](Uses-Cleanup-Preview-compiler-verified-this-unit) | drag-lint > Uses & Dependencies > Uses Cleanup Preview (compiler-verified, this unit)...; `uses-fix` |  |

## Component conversion

Rule-driven migration of legacy component types.

| Feature | Surfaces | Status |
|---|---|---|
| [convert-apply](convert-apply) | `convert-apply` |  |
| [convert-reemit](Maintenance) | `convert-reemit` | internal |
| [convert-scaffold](convert-scaffold) | `convert-scaffold` |  |
| [convert-validate](convert-validate) | `convert-validate` |  |
| [ConvRulesEditor](Features) | `ConvRulesEditor.exe` |  |
| [glyph-vacuum](Features) | `glyph-vacuum` |  |
| [proptree](proptree) | `proptree` |  |

## Graphs and reports

Call graphs, dependency reports, dead code, tester spreadsheets.

| Feature | Surfaces | Status |
|---|---|---|
| [butterfly](butterfly) | `butterfly` |  |
| [Call Graph (Butterfly)](Call-Graph-Butterfly) | drag-lint > Uses & Dependencies > Call Graph (Butterfly)...; `reverse-calltree` |  |
| [callgraph](callgraph) | `callgraph` |  |
| [Circular Dependency Report (worked example)](Circular-Dependency-Report) | procedure: `docs\wiki\Circular-Dependency-Report.md` |  |
| [Circular Uses Report (cycles + fix plan)](Circular-Uses-Report-cycles-fix-plan) | drag-lint > Uses & Dependencies > Circular Uses Report (cycles + fix plan)...; `cycles` |  |
| [deps-report](deps-report) | `deps-report`; drag-lint > Uses & Dependencies > Dependency Report (third-party rollup)... |  |
| [Export Enums (Delphi const)](Export-Enums-Delphi-const) | drag-lint > Generate & Export > Export Enums (Delphi const)...; `export enums` |  |
| [Export Graph (DOT)](Export-Graph-DOT) | drag-lint > Generate & Export > Export Graph (DOT)...; `graph` |  |
| [Export to Obsidian](Export-to-Obsidian) | drag-lint > Generate & Export > Export to Obsidian...; `export obsidian` |  |
| [Find Dead Code](Find-Dead-Code) | drag-lint > Code Quality > Find Dead Code...; `find-deadcode` |  |
| [Forms for testers (CSV)](Generate-Test-Helper-CSV) | drag-lint > Reports > Forms for testers (CSV)...; `forms-csv` |  |
| [Impact / Blast Radius (symbol)](Impact-Blast-Radius-symbol) | drag-lint > Uses & Dependencies > Impact / Blast Radius (symbol)...; `impact` |  |
| [Reverse Call Tree (clickable, Messages window)](Reverse-Call-Tree-clickable-Messages-window) | `reverse-calltree` |  |
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
| [ask (engine verb)](Diagrams-and-Charts) |  | planned |
| [Chart questions](Diagrams-and-Charts) | 25 questions; `charts\src\Ask-Report.ps1`; `charts\src\New-DiagramArtifact.ps1` |  |
| [Charts and the IDE](Charts-and-the-IDE) | procedure: `docs\wiki\Charts-and-the-IDE.md` |  |

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
| [ghost-check](ghost-check) | `ghost-check` |  |
| [ghost-recover](ghost-recover) | `ghost-recover` |  |
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
| [IDE Menu Reference](IDE-Menu-Reference) | procedure: `docs\wiki\IDE-Menu-Reference.md` |  |
| [ide-release](ide-release) | `ide-release` |  |
| [Installation](Installation) | `drag-lint.exe`; procedure: `docs\wiki\Installation.md` |  |
| [lsp](lsp) | `lsp` |  |
| [serve](serve) | `serve` |  |
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
| [dump-pp-eval](Maintenance) | `dump-pp-eval` | internal |
| [dump-pp-lex](Maintenance) | `dump-pp-lex` | internal |
| [dump-refs](dump-refs) | `dump-refs` |  |
| [Feature registry](Feature-Registry) | `tools\feature-registry.ps1 add / update / find / blast-radius / move-menu / deprecate / normalise / check / generate`; `tools\build-feature-pages.ps1 -Check -OutDir -Normalise`; `tools\publish-release.ps1 -Version -DryRun`; procedure: `docs\wiki\Feature-Registry.md` |  |
| [info](info) | `info` |  |
| [Library Drift Check](Library-Drift-Check) | drag-lint > Index & Maintenance > Library Drift Check...; `library-drift` |  |
| [Maintenance](Maintenance) | procedure: `docs\wiki\Maintenance.md` |  |
| [Open Plugin Log](Open-Plugin-Log) | About window: Open Plugin Log |  |
| [resolve-uses](Maintenance) | `resolve-uses` | internal |
| [selftest](Maintenance) | `selftest` | internal |
| [shutdown](Features) | `shutdown` |  |
| [sql](sql) | `sql` |  |
| [test-store-freshness](Maintenance) | `test-store-freshness` | internal |

---

*Generated by `tools\build-feature-pages.ps1` from `features\`; counts come from `drag-lint rules --json` at generation time. Do not edit by hand.*
