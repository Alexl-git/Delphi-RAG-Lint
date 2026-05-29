# v0.31 — Compiler-less Diagnostics + Library Indexing Toggle

**Date:** 2026-05-29
**Status:** Design approved
**Branch:** `v0.31-zed-friendly` off `main`

## 1. Goal

Two independent improvements:

1. **Pure-AST diagnostics** — diagnostic rules that need only the
   tree-sitter parse + the symbol index, no `dcc.exe`. Makes the LSP
   actually useful in Zed / VS Code where dcc may not be present.
2. **Library indexing toggle** — plugin auto-index honors a new
   "include libraries" setting that adds `--scan-libraries` to the
   spawned index command. Off by default (heavy).

## 2. F1 — Compiler-less diagnostics

### 2.1 ERROR-node detection

The tree-sitter-delphi13 grammar yields ERROR nodes when it bails on
malformed syntax. A pure-AST query catches these:

`rules/parser-error.scm`:
```
((ERROR) @warn)
```

`rules/parser-error.json`:
```json
{
  "id": "parser-error",
  "severity": "error",
  "message": "Syntax error (parser failed to recognize this construct)",
  "warn_capture": "warn"
}
```

### 2.2 Undeclared identifier detection (cross-unit walk)

Programmatic check (not pure .scm — needs index lookups):

For every `(exprCall entity: (identifier))` and `(exprDot rhs: (identifier))`:
1. Extract the identifier text.
2. Query the symbol store: `FindSymbolsByExactName(name)`.
3. If no symbol found in this file or its dependency closure → emit
   `undeclared-identifier` diagnostic.

Implementation: new module `src/diagnostics/DRagLint.Diagnostics.AstChecks.pas`
with class `TAstChecker.CheckUndeclared(store, file): TArray<TLintFinding>`.

`drag-lint check-ast <file>` CLI command runs the AST checks against
the indexed corpus, emits findings in the same format as `lint`. Both
sets flow through the same `publishDiagnostics` path.

Limitation: false positives for stdlib types (System.TObject, etc.)
when the index doesn't cover them. Mitigation: ship a baseline
allowlist of known Delphi RTL symbols (~200 names) bundled with the
binary at `<exedir>/rules/builtin-symbols.txt`.

### 2.3 Mismatched begin/end depth

Walk the source counting `begin` and `end` keywords inside method
bodies. When depth goes negative or finishes non-zero, flag.

`rules/unbalanced-begin-end.scm` — pure tree-sitter query checking
`(defProc body: (_) @body)` with a `#match?` predicate isn't quite
right (regex doesn't count). Implement as programmatic check in
TAstChecker.

### 2.4 Common typo: `=` vs `:=` in statement position

Match `(exprBinary op: "=")` where the parent is a statement (not
an expression). This is hard to express precisely without parent
context — punt to programmatic AST walk.

### 2.5 Tools menu entry

`Tools → drag-lint → Run AST Checks` — spawns
`drag-lint check-ast <active-file>`, broadcasts didSave for refresh.

## 3. F2 — Library indexing toggle

Settings extension:

```
TDragLintSettings = record
  ... existing ...
  ScanLibraries: Boolean;  // default False
end;
```

`HKCU\Software\drag-lint\DelphiPlugin\ScanLibraries` REG_DWORD.

In `TDragLintProjectNotifier.FileNotification` (ofnFileOpened on .dproj):
- Read setting.
- If True: command becomes `drag-lint index <projdir> --project <projfile> --scan-libraries --db <projdb>`
- If False: existing `drag-lint index <projdir> --db <projdb>`

In `DragLint.Plugin.OptionsFrame.pas` add a checkbox `Scan libraries
(RTL + DevExpress + browsing paths)` under the AutoIndex group.

## 4. CLI surface

New: `drag-lint check-ast <file> [--db PATH] [--format text|json]`

Reuses the lint reporting format. Findings have `source = 'drag-lint-ast'`
to distinguish from the .scm rule pack (`source = 'drag-lint'`) and
compiler (`source = 'dcc'`).

## 5. MCP tool

`run_ast_checks`:
```json
{"target": "path.pas", "db": "..."}
```

Returns findings array same shape as `run_compile_check`.

## 6. New units / modules

- `src/diagnostics/DRagLint.Diagnostics.AstChecks.pas`
- `rules/parser-error.scm` + `.json`
- `rules/builtin-symbols.txt` (allowlist for undeclared check)

## 7. Modified

- `src/cli/DRagLint.CLI.pas` — DoCheckAst dispatch
- `src/mcp/DRagLint.MCP.Server.pas` — run_ast_checks tool
- `src/delphi-plugin/DragLint.Plugin.Settings.pas` — ScanLibraries field
- `src/delphi-plugin/DragLint.Plugin.SettingsForm.pas` — checkbox
- `src/delphi-plugin/DragLint.Plugin.OptionsFrame.pas` — checkbox
- `src/delphi-plugin/DragLint.Plugin.ProjectNotifier.pas` — pass --scan-libraries when setting is true
- `src/delphi-plugin/DragLint.Plugin.Editor.pas` — Run AST Checks menu entry

## 8. Stop criteria

### Auto-verifiable

1. `drag-lint check-ast tests/fixtures/RuleTest.pas` exits 0 with some findings.
2. T53 — parser-error rule fires on a hand-crafted broken .pas file.
3. T54 — settings round-trip with ScanLibraries field.
4. BPL builds clean.
5. All prior tests pass.

### Manual

6. In RAD Studio with v0.31 BPL installed, the plugin spawns drag-lint
   with --scan-libraries when the user has enabled the setting and
   opens a .dproj.
7. `Tools → drag-lint → Run AST Checks` produces findings even
   without dcc.exe being on PATH.

## 9. Out of scope (carried to v0.32+)

- Mouse-hover tooltip (v0.32)
- Real-time editor-buffer parsing (v0.33+)
- Type-aware diagnostics (waits on refs.symbol_id population)
- Cross-project workspace mode (v0.34)
- Pre-built MSI (v0.35)

## 10. Push cadence

Spec → push. F1 + F2 land → push. Tag + release.
