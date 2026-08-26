# Feature Index

Every documented feature, by the surface it is reached from. Generated
from the feature map, which is derived from the shipping build -- the CLI
usage banner and the plugin's own menu registration.

See also [Features](Features) for the grouped overview and
[IDE Menu Reference](IDE-Menu-Reference) for the menu layout.

## Main menu

* [Add Missing Units to uses (whole unit)...](Add-Missing-Units-to-uses-whole-unit) -- `check-unit`
* [Auto-Document Whole Project...](Auto-Document-Whole-Project) -- `index + document`
* [Call Graph (Butterfly)...](Call-Graph-Butterfly) -- `reverse-calltree`
* [Circular Uses Report (cycles + fix plan)...](Circular-Uses-Report-cycles-fix-plan) -- `cycles` (worked example: [Circular Dependency Report](Circular-Dependency-Report))
* [Class Surface...](Class-Surface) -- `surface`
* [Compile & Diagnose](Compile-Diagnose)
* [Compile Buffer (unsaved)](Compile-Buffer-unsaved)
* [Compiler Hints...](Compiler-Hints) -- `query hints`
* [Copy Diagnostics (Current File)](Copy-Diagnostics-Current-File) -- `lint`
* [Doc Comment Stub (symbol)...](Doc-Comment-Stub-symbol) -- `generate-docs`
* [drag-lint Graph (dockable)](drag-lint-Graph-dockable)
* [drag-lint Options...](drag-lint-Options)
* [drag-lint Panel (dockable)](drag-lint-Panel-dockable)
* [Export Enums (Delphi const)...](Export-Enums-Delphi-const) -- `export enums`
* [Export Graph (DOT)...](Export-Graph-DOT) -- `graph`
* [Export to Obsidian...](Export-to-Obsidian) -- `export obsidian`
* [Find Dead Code...](Find-Dead-Code) -- `find-deadcode`
* [Find Undocumented (public)...](Find-Undocumented-public) -- `query find`
* [Find Usages...](Find-Usages)
* [Format Whole Project with YADF...](Format-Whole-Project-with-YADF) -- `format + index`
* [Format with YADF](Format-with-YADF) -- `format`
* [Full Compile Sweep](Full-Compile-Sweep) -- `refresh-findings`
* [Generate Test Helper CSV...](Generate-Test-Helper-CSV) -- `forms-csv`
* [Go to Definition](Go-to-Definition)
* [Hover at Cursor](Hover-at-Cursor) -- `hover`
* [Impact / Blast Radius (symbol)...](Impact-Blast-Radius-symbol) -- `impact`
* [Import Build Log...](Import-Build-Log) -- `import-log`
* [Library Drift Check...](Library-Drift-Check) -- `library-drift`
* [Lint Buffer (Unsaved)](Lint-Buffer-Unsaved) -- `lint`
* [Open Plugin Log](Open-Plugin-Log)
* [Quick-Fix: Add Unit for Inline Hint (H2443) at Cursor](Quick-Fix-Add-Unit-for-Inline-Hint-H2443-at-Cursor)
* [Quick-Fix: Add Unit for Undeclared at Cursor (Ctrl+Alt+U)](Quick-Fix-Add-Unit-for-Undeclared-at-Cursor-Ctrl-Alt-U)
* [Quick-Fix: Convert Public Field to Property at Cursor](Quick-Fix-Convert-Public-Field-to-Property-at-Cursor)
* [Rebuild Index for This Project](Rebuild-Index-for-This-Project) -- `index`
* [Reconcile Project Members (.dpr/.dproj)...](Reconcile-Project-Members-dpr-dproj) -- `reconcile-project`
* [Recover Buffer-Compile Files](Recover-Buffer-Compile-Files)
* [Rename Symbol...](Rename-Symbol) -- `rename`
* [Reverse Call Tree (clickable, Messages window)...](Reverse-Call-Tree-clickable-Messages-window) -- `reverse-calltree`
* [Reverse Call Tree (who calls this, N-deep)...](Reverse-Call-Tree-who-calls-this-N-deep) -- `reverse-calltree`
* [Run AST Checks](Run-AST-Checks) -- `check-ast`
* [Run Diagnostics (didSave)](Run-Diagnostics-didSave)
* [Run Lint All (Full Report)...](Run-Lint-All-Full-Report) -- `lint-all`
* [Scan TODOs / FIXMEs...](Scan-TODOs-FIXMEs) -- `todos`
* [Show Completion](Show-Completion)
* [Show Resolved DBs (debug)...](Show-Resolved-DBs-debug) -- `resolve-dbs`
* [Show Signature Help](Show-Signature-Help)
* [Show Structure](Show-Structure)
* [Show Wiring (Spring4D DI + DFM events)...](Show-Wiring-Spring4D-DI-DFM-events) -- `wiring`
* [Symbol Search...](Symbol-Search) -- `query`
* [Symbol Slice...](Symbol-Slice) -- `slice`
* [Top Symbols (fan-in)...](Top-Symbols-fan-in) -- `top`
* [Type at Cursor](Type-at-Cursor) -- `typeat`
* [Unit Test Stub (symbol)...](Unit-Test-Stub-symbol) -- `generate-test`
* [Uses Audit -- interface->impl moves + unused (this unit)...](Uses-Audit-interface-impl-moves-unused-this-unit) -- `uses-audit`
* [Uses Cleanup Preview (compiler-verified, this unit)...](Uses-Cleanup-Preview-compiler-verified-this-unit) -- `uses-fix`
* [Uses Report (CSV)...](Uses-Report-CSV) -- `uses-report`

## Right-click menus

* [Allow this message](Allow-this-message) -- `allow`
* [Copy All Diagnostics](Copy-All-Diagnostics) -- `lint`
* [Create helper class](Create-helper-class) -- `create-enum-helper`
* [Document it](Document-it) -- `document`
* [Document project](Document-project) -- `document`
* [Document unit](Document-unit) -- `document`
* [drag-lint: Project Rules...](drag-lint-Project-Rules) -- `rules`
* [Find Usages (context)](Find-Usages-context) -- `usages`
* [Fix all in project](Fix-all-in-project) -- `lint-all (autofix)`
* [Fix all in unit](Fix-all-in-unit) -- `lint (autofix)`
* [Fix it](Fix-it) -- `lint (autofix)`
* [Go to Declaration](Go-to-Declaration)
* [Go to Implementation](Go-to-Implementation)
* [Show in Call Graph](Show-in-Call-Graph) -- `reverse-calltree`

## Tool windows

* [drag-lint](drag-lint)
* [drag-lint Graph](drag-lint-Graph)

## CLI verbs

* [allow](allow) -- `allow`
* [ambiguous-calls](ambiguous-calls) -- `ambiguous-calls`
* [bench-context](bench-context) -- `bench-context`
* [butterfly](butterfly) -- `butterfly`
* [call-path](call-path) -- `call-path`
* [callgraph](callgraph) -- `callgraph`
* [compile-check](compile-check) -- `compile-check`
* [context](context) -- `context`
* [convert-apply](convert-apply) -- `convert-apply`
* [convert-scaffold](convert-scaffold) -- `convert-scaffold`
* [convert-validate](convert-validate) -- `convert-validate`
* [create-enum-helper](create-enum-helper) -- `create-enum-helper`
* [deps-report](deps-report) -- `deps-report`
* [diff](diff) -- `diff`
* [doc-drift](doc-drift) -- `doc-drift`
* [document-all](document-all) -- `document-all`
* [dump-call-edges](dump-call-edges) -- `dump-call-edges`
* [dump-refs](dump-refs) -- `dump-refs`
* [extract-method](extract-method) -- `extract-method`
* [fb-snapshot](fb-snapshot) -- `fb-snapshot`
* [find-callees](find-callees) -- `find-callees`
* [find-unit](find-unit) -- `find-unit`
* [ghost-check](ghost-check) -- `ghost-check`
* [ghost-recover](ghost-recover) -- `ghost-recover`
* [helpers-of](helpers-of) -- `helpers-of`
* [info](info) -- `info`
* [link-orm](link-orm) -- `link-orm`
* [lint-project](lint-project) -- `lint-project`
* [lsp](lsp) -- `lsp`
* [migrate-dbs](migrate-dbs) -- `migrate-dbs`
* [outline](outline) -- `outline`
* [pp-profile](pp-profile) -- `pp-profile`
* [preprocess-file](preprocess-file) -- `preprocess-file`
* [proptree](proptree) -- `proptree`
* [purge-locals](purge-locals) -- `purge-locals`
* [query ancestors](query-ancestors) -- `query ancestors`
* [query find-callers](query-find-callers) -- `query find-callers`
* [query typecat](query-typecat) -- `query typecat`
* [query type-usage](query-type-usage) -- `query type-usage`
* [rules](rules) -- `rules`
* [safe-delete](safe-delete) -- `safe-delete`
* [schema](schema) -- `schema`
* [serve](serve) -- `serve`
* [shared-unit](shared-unit) -- `shared-unit`
* [usages](usages) -- `usages`
* [workspace add](workspace-add) -- `workspace add`
* [workspace index](workspace-index) -- `workspace index`
* [workspace status](workspace-status) -- `workspace status`


