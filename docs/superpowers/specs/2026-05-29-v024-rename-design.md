# v0.24 — Rename Symbol

**Date:** 2026-05-29
**Status:** Design approved, ready for plan
**Branch:** `v0.24-rename` off `main`

## 1. Goal

Add `drag-lint rename` — rewrite every occurrence of a symbol by qualified
name. Foundation for further refactoring (extract method, inline) in
v0.25+.

## 2. Features

### 2.1 `drag-lint rename --qname Foo.TBar.Baz --to NewName [--dry-run] [--db PATH]`

1. Resolve the symbol by qname.
2. Find the symbol's declaration site (file + line + col + token length).
3. Find every `refs` row whose `name_text` matches the symbol's short name
   in the same case-insensitive sense Delphi uses.
4. Build an edit set: for each location, replace the token with the new
   name.
5. If `--dry-run`: print one line per edit `<file>:<line>:<col>  <old> -> <new>`.
6. Else: apply edits in place (writing each file with the v0.4 ANSI
   encoding the indexer uses; preserve CRLF line endings).
7. Report N edits across M files.
8. Recommend the user re-run `drag-lint index` to refresh the index after
   a rename.

### 2.2 Safety guards

- **Case-insensitive name match** (Delphi convention). Reject the rename
  if `LowerCase(OldName) <> LowerCase(NewName)` AND the new name would
  collide with an existing top-level symbol in the same scope.
- **Skip qualifier-only edits** — `Foo.TBar.Baz` where the user wants
  to rename `Baz` to `NewBaz`: rewrite `Baz` but leave `Foo.TBar.` alone.
  (Implementation: only edit the token at the ref's exact column range.)
- **DFM event-handler bindings** — when renaming a method whose
  `name_text` matches an `event-binding` ref in the DFM, also rewrite the
  .dfm file. This is critical for forms.
- **Backup** — write `<file>.bak` next to each modified file unless
  `--no-backup` is passed.

### 2.3 What's NOT done in v0.24

- No overrides walk (renaming `TBase.Foo` won't also rename
  `TDerived.Foo` overrides unless they happen to share the same name match
  — which they do, so they get renamed; but this is name-based, not
  inheritance-aware).
- No conflict detection beyond top-level collision (param-name shadowing
  is on the user).
- No undo via .bak restore CLI (user does it manually).
- No interactive rewrite (it's batch).

## 3. CLI surface

```
drag-lint rename --qname Foo.TBar.Baz --to NewBaz [--db PATH] [--dry-run] [--no-backup]
```

Exit codes:
- 0: success (edits applied or dry-run printed)
- 1: symbol not found
- 2: collision detected
- 3: I/O error during apply

## 4. MCP tool

`rename_symbol`:
```json
{
  "qname": "Foo.TBar.Baz",
  "to": "NewBaz",
  "dry_run": true,
  "db": "..."
}
```

Returns:
```json
{
  "edits": [
    {"file": "...", "line": 12, "col": 5, "old": "Baz", "new": "NewBaz"},
    ...
  ],
  "files_touched": 3,
  "applied": false
}
```

## 5. Plugin (IDE)

Add menu entry `Tools > drag-lint > Rename Symbol...` with a simple input
dialog:
- Prompt: `Rename <current symbol> to:`
- The current symbol is read from cursor position via TTypeAtResolver
- If user OKs: send `rename_symbol` request to drag-lint via the existing
  LSP client (or shell out to `drag-lint rename` for v0.24 simplicity)
- Display result count via ShowMessage

## 6. Storage additions

None. Pure read + write across existing data.

## 7. New module

- `src/refactor/DRagLint.Refactor.Rename.pas` — TRenameRefactoring class:
  - `Build(store, qname, newName) → TArray<TRenameEdit>` (computes edits)
  - `Apply(edits, backup): Boolean` (applies in-place, writes .bak)
  - `RenderDryRun(edits): string` (text format)

## 8. Test fixtures

- T35_rename_dry.bat: rename in a copy of Calls.pas, verify edit output
- T36_rename_apply.bat: rename + verify file content changed + .bak created
- T37_mcp_rename.bat: MCP tool round-trip

## 9. Stop criteria

1. `drag-lint rename --qname Calls.TWidget.Compute --to Calc --db <t14> --dry-run`
   prints 4 expected edits (1 declaration + 3 callers in Calls.pas).
2. `drag-lint rename --qname Calls.TWidget.Compute --to Calc --db <t14>`
   actually rewrites Calls.pas, creates Calls.pas.bak, exits 0.
3. MCP `rename_symbol` works.
4. v0.16-v0.23 tests still pass.

## 10. Out of scope (carried to v0.25)

- Workspace mode (cross-project rename when multiple projects share
  symbols)
- Refactor preview UI in plugin (dry-run dialog showing per-file diff)
- Inheritance-aware overrides walk
- Extract method
- Inline method

## 11. Push cadence

Spec → push.
Feature ships → push.
Tag + GitHub release after all features.
