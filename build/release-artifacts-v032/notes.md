## v0.32.0-alpha -- 2026-05-29

### Added

- **Inline code lens** -- `TDragLintCodeLensCache` populates per-file
  symbol caller counts on `EditorViewActivated`. `PaintLine` renders
  dim grey `[N callers]` text next to method declarations. New setting
  `EnableCodeLens` (default True) gates the feature; available in both
  Tools > drag-lint > Settings and Tools > Options > drag-lint.

- **4 new tree-sitter-query lint rules** (shippable subset of planned 6):
  - `compiler-magic-comments` (info) -- flags comments containing
    TODO/FIXME/HACK/XXX.
  - `nested-with` (warning) -- flags nested `with` statements where
    scope ambiguity becomes exponential.
  - `assert-call` (info) -- flags every `Assert()` call; reminder to
    include the descriptive second argument.
  - `case-magic-numbers` (info) -- flags integer literals as case
    branch labels; consider naming the constant.

  Rules not shipped (grammar limitations): `try-without-finally` (no
  `kTry` node target), `result-assignment-after-exit` (requires flow
  analysis). With v0.28 (5 rules), v0.31 (`parser-error`), and v0.32
  (4 rules), drag-lint ships **10 built-in lint rules** plus 3
  programmatic AST checks.

- **New unit** `DragLint.Plugin.CodeLensCache` -- singleton
  `TDragLintCodeLensCache` (get/set/invalidate/populate); registered in
  both `.dpk` and `.dproj`.

- **T55** -- CodeLensCache smoke test (get, invalidate, clear, singleton
  identity).

- **T56** -- v0.32 lint rule pack smoke test (all 4 rules fire on
  `RuleTest.pas`).