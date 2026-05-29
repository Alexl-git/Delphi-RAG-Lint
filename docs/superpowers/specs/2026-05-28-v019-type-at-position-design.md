# v0.19 — Type-At-Position

**Date:** 2026-05-28
**Status:** Design approved (pragmatic scope), ready for plan
**Branch:** `v0.19-type-at-position` off `v0.18-context-bundles`

## 1. Goal

Given a file path + line + column, return:
1. The containing symbol (always — uses existing line-range lookup).
2. The identifier token at the position (if any).
3. The type or symbol that identifier resolves to (when resolvable from the symbol index alone).
4. For dotted access `X.Y` where X resolves to a class/record/interface, the member Y's signature.

Foundation for v0.20 LSP completion and v0.21 OTAPI plugin.

## 2. Scope honest take

**In scope (tractable from the index):**
- Identifier matching a top-level class / record / interface / enum / unit symbol
- Identifier matching a method / procedure / function (returns signature)
- Identifier matching a property / field on a class found via parent context
- Dotted access `ClassName.Member` or `UnitName.ClassName`
- The containing-symbol lookup (always works)

**Out of scope (defer to v0.21 OTAPI):**
- Local variable type inference (would need per-method scope table)
- Function-call type propagation (`Foo(x).Bar` requires return-type inference)
- Generic instantiation (`TList<TFoo>.Items[i]` requires type substitution)
- With-statement scope tricks
- Implicit type coercions

These are properly the job of the Delphi compiler's own type system, which v0.21 will tap via OTAPI. v0.19 ships the precision-perfect cases and clearly declines the ambiguous ones.

## 3. Command

```
drag-lint typeat <file>:<line>:<col> [--db PATH] [--format text|json]
```

`<file>` may be absolute or relative to cwd. `<line>` 1-based, `<col>` 1-based (matches editor conventions).

## 4. Output

### text

```
File:         tests/fixtures/Calls.pas
Position:     line 17, col 12
Containing:   Calls.TWidget.Run
Token:        Compute
Resolved:     Calls.TWidget.Compute (method)
Signature:    function Compute(N: Integer): Integer
Doc:          (none)
```

If unresolved:
```
File:         tests/fixtures/Calls.pas
Position:     line 5, col 8
Containing:   Calls.TWidget
Token:        items
Resolved:     unresolved (likely a local variable; v0.19 does not infer)
```

### json

```json
{
  "file": "tests/fixtures/Calls.pas",
  "line": 17,
  "col": 12,
  "containing": {"qname": "Calls.TWidget.Run", "kind": "method"},
  "token": "Compute",
  "resolved": {
    "qname": "Calls.TWidget.Compute",
    "kind": "method",
    "signature": "function Compute(N: Integer): Integer",
    "file": "tests/fixtures/Calls.pas",
    "line": 18
  },
  "doc": null
}
```

## 5. Resolution algorithm

1. Read the source file. Locate `<line>` (1-based).
2. Extract the identifier at `<col>`. Walk left and right while characters are `[A-Za-z0-9_]`. If column is on whitespace or punctuation, identifier is empty.
3. Look at the character immediately before the identifier:
   - `.` → dotted access. Walk left to extract the LHS identifier or qualified chain.
   - Anything else → bare identifier.

4. **Containing symbol**: SQL — find symbol whose file_id matches AND `<line>` in [start_line..end_line], pick innermost (highest start_line).

5. **Bare identifier resolution** (in order, stop at first hit):
   a. Exact name match in `symbols` where `file_id` of containing symbol's parent (= same unit). Pick first.
   b. Exact name match in `symbols` across all units.
   c. If still no match: try fuzzy (existing trigram path) and return top match with confidence note.
   d. Otherwise: return "unresolved".

6. **Dotted access `X.Y`**:
   a. Resolve X using bare identifier rules.
   b. If X is a class/record/interface: lookup Y as a child symbol of X (parent_id = X.id).
   c. If X is a unit name: lookup Y as a top-level symbol whose qname starts with `X.`.
   d. Otherwise: return "unresolved at .Y; X resolved to non-container kind".

7. **Doc lookup**: if Resolved.id present, call existing `GetSymbolDoc`. Attach.

## 6. Schema impact

None. v0.19 is read-only over existing tables.

## 7. Storage additions

Add to `ISymbolStore` + `TSQLiteSymbolStore`:
```pascal
function FindContainingSymbol(AFileId: Int64; ALine: Integer): TSymbol;
function FindSymbolByNameInFile(AFileId: Int64;
  const AName: string): TSymbol;
function ResolveDottedAccess(const AContainerQName, AMemberName: string;
  out AResolved: TSymbol): Boolean;
```

`FindContainingSymbol` SQL:
```sql
SELECT * FROM symbols
WHERE file_id = :fid AND start_line <= :line AND end_line >= :line
ORDER BY start_line DESC LIMIT 1
```

## 8. CLI / MCP / LSP

**CLI:** `drag-lint typeat <file>:<line>:<col> [--format text|json]`

**MCP:** new tool `get_type_at_position`:
```json
{"file": "...", "line": 12, "col": 5, "db": "..."}
```

**LSP:** Extend the existing `textDocument/hover` handler to include type resolution when the symbol at position has children-of-parent-class-of-token info. Falls back to v0.16 doc hover when no extra info.

(Note: LSP server already does symbol-at-position lookup for hover/definition. v0.19 just adds the dotted-access enrichment.)

## 9. Test fixtures

Reuse `tests/fixtures/Calls.pas` (has `TWidget`, `Compute`, `Run`).

Test cases:
- (file, line 16, col 6) → "Compute" inside Run method → resolves to TWidget.Compute.
- (file, line 17, col 8) → "Compute" inside the call → resolves to TWidget.Compute.
- (file, line 1, col 6) → "Calls" (the unit name) → resolves to unit symbol.
- A position on a local variable → returns "unresolved".

## 10. Stop criteria

1. `drag-lint typeat Calls.pas:16:6` resolves "Compute" to TWidget.Compute (or similar).
2. JSON format returns valid JSON.
3. Containing symbol correctly identified for every position inside a known method.
4. Unresolved positions return a clear "unresolved" payload, not an error.
5. MCP `get_type_at_position` works.
6. v0.16-v0.18 tests still pass.

## 11. Out of scope (carried to v0.21)

- Local variable types (parser doesn't emit var declarations as searchable symbols today)
- Procedure parameter types
- Generic type substitution
- With-statement scope tracking
- Function-return-type propagation through expressions
