# v0.25 — Refactor Polish + Doc Stubs + Dead Code

**Date:** 2026-05-29
**Status:** Design approved
**Branch:** `v0.25-refactor-preview` off `main`

## 1. Goal

Three small, independent features that round out v0.24's rename work.

## 2. Features

### 2.1 Refactor preview form (replaces v0.24 InputBox)

Upgrade `InvokeRename` in the plugin to a proper VCL form:
- Form fields: `Symbol qname:` (TEdit), `New name:` (TEdit), `Dry-run only` (TCheckBox, default ON), `Write backups` (TCheckBox, default ON)
- Buttons: `Preview` (runs `drag-lint rename --dry-run` and shows the edit list in a TMemo on the same form), `Apply` (re-runs without `--dry-run`), `Cancel`
- Synchronous subprocess spawn via existing `TDragLintLspClient` style of CreateProcessW + pipe capture (new lightweight helper since we need stdout)
- Status label at bottom

New unit: `src/delphi-plugin/DragLint.Plugin.RefactorForm.pas`

### 2.2 Doc stub generator

New CLI: `drag-lint generate-docs --qname Foo.TBar.Baz [--format xmldoc|pasdoc]`

For the given symbol:
1. Pull its signature.
2. Parse the parameter list.
3. Emit a Markdown-friendly doc stub:

XMLDoc format:
```
/// <summary>TODO: describe</summary>
/// <param name="value">TODO: describe</param>
/// <returns>TODO: describe</returns>
```

PasDoc format:
```
{**
 * TODO: describe
 * @param value TODO: describe
 * @returns TODO: describe
 *}
```

Prints the stub to stdout. User pipes/redirects to clipboard or paste into source.

MCP: `generate_doc_stub` tool with same args.

New module: `src/refactor/DRagLint.Refactor.DocStub.pas`

### 2.3 Dead-code finder

New CLI: `drag-lint find-deadcode [--kind method|function|...] [--db PATH] [--include-private]`

Walks the index:
1. For each symbol of the chosen kind:
2. If `FindCallersByName(name).Count = 0` AND the symbol is not the entry point (`Main`, `initialization`, `Register`, etc.) AND not a constructor/destructor:
3. Emit `<qname>  [<kind>]  <file>:<line>`

This is the inverse of `impact`. Useful for "what can I delete?"

MCP: `find_deadcode` tool.

## 3. Schema impact

None.

## 4. New units / modules

- `src/refactor/DRagLint.Refactor.DocStub.pas`
- `src/refactor/DRagLint.Refactor.DeadCode.pas`
- `src/delphi-plugin/DragLint.Plugin.RefactorForm.pas`

## 5. Modified

- `src/cli/DRagLint.CLI.pas` — DoGenerateDocs, DoFindDeadcode, dispatch
- `src/mcp/DRagLint.MCP.Server.pas` — 2 new tools
- `src/delphi-plugin/DragLint.Plugin.Editor.pas` — InvokeRename uses new form

## 6. Storage helper (one new method)

`FindSymbolsWithNoCallers(AKind: string; AIncludePrivate: Boolean): TArray<TSymbol>`

SQL:
```sql
SELECT s.* FROM symbols s
LEFT JOIN refs r ON r.name_text = s.name
WHERE r.id IS NULL
  AND (:kind = '' OR s.kind = :kind)
  AND s.name NOT IN ('Main', 'Register', 'initialization', 'finalization')
  AND (:includePrivate = 1 OR (s.modifiers IS NULL OR s.modifiers NOT LIKE '%private%'))
```

## 7. Stop criteria

1. `drag-lint generate-docs --qname Calls.TWidget.Compute` prints an XMLDoc stub.
2. `drag-lint find-deadcode --kind method --db <db>` lists symbols with 0 refs.
3. MCP `generate_doc_stub` + `find_deadcode` return valid JSON.
4. Plugin Rename Symbol... shows the new form, Preview button populates the memo.
5. v0.16-v0.24 tests still pass.

## 8. Out of scope

- IDE inline doc-stub insertion (currently CLI only; plugin would need `IOTAEditWriter` integration — v0.26+)
- Cross-project dead-code detection (single-DB scope)
- Smart dead-code (some methods are reachable via DFM event-binding only — those are covered by `refs` already, but if a method is only called by reflection it gets flagged as dead)

## 9. Push cadence

Spec → push. Each feature → push. Tag + release after all three.
