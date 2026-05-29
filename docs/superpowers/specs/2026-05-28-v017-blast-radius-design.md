# v0.17 — Blast-Radius Pack

**Date:** 2026-05-28
**Status:** Design approved (rolled forward from v0.16 roadmap section), ready for plan
**Slice:** Part of v0.17 follow-up to Slice A (doc extraction)
**Branch:** `v0.17-blast-radius` off `v0.16-doc-extraction`

## 1. Goal

Four small CLI features that turn drag-lint from "find one symbol" into "understand the
surface and reach of a symbol." All four are tuned for the AI-consumer use case the v0.16
positioning note flagged: cut Claude's per-task token cost on Delphi codebases by an
order of magnitude.

## 2. Features

### 2.1 `drag-lint impact --qname <Foo.Bar> [--depth N] [--format text|json]`

Transitive caller graph up to depth N (default 3). Output:

```
Foo.TBar.Baz
  Depth 1:  12 callers in 5 units
  Depth 2:  47 callers in 11 units (+35)
  Depth 3: 184 callers in 39 units (+137)
  Touches: 3 forms, 2 frames, 1 background service, 0 unit-tests
```

JSON format returns the structured graph for tool consumption.

**Recursion:** Walk `refs.name_text` matches → find containing symbol → recurse on that
symbol's name. Same name-based imprecision the existing `find-callers` accepts in v0.16
(refs.symbol_id resolution is parked as v0.22 work per the Graphify-inspired Slice C).

### 2.2 `drag-lint surface --qname <TFoo> [--include-impl] [--format text|json]`

Class/record interface only. Reads the source file and returns:
- The `type` block for the class (declaration line through `end;`)
- All public/published method signatures (no bodies)
- All properties
- Skip private/protected sections unless `--all-visibility` flag is set

Cuts the "what does this class do" turn from ~8k tokens to ~800 on typical VCL classes.

Symbol resolution: target must be `skClass`, `skRecord`, or `skInterface`. Otherwise
exit 2 with a usage hint.

### 2.3 `drag-lint slice --qname <Foo.TBar> [--format text|json]`

Symbol-relevant chunks of the containing unit. Output is the unit `unit` header + the
class declaration + only the implementation methods that belong to `TBar` (and any
trailing `end.`). Discards unrelated symbols in the same unit.

Roughly 70% smaller than reading the whole unit. Useful for "Claude, modify TBar's
methods" turns.

### 2.4 `drag-lint query find-callers --context N`

Existing `find-callers` is extended with `--context N` (default 0). When N > 0, each
caller row is followed by N lines of surrounding source:

```
Foo.pas:123: x := TBar.Baz(y);
  121: var
  122:   y: Integer;
  123:   x: string;
  124: begin
  125:   y := 42;
```

Removes the "I need to read this file" follow-up step. Cuts token cost on caller
inspection by ~80%.

## 3. Schema impact

**None.** All four features are pure read paths over existing tables (symbols, refs,
files). No DDL, no migration.

## 4. Storage additions

In `DRagLint.Storage.SQLite.pas`, add three new methods to `ISymbolStore`:

```pascal
function FindTransitiveCallers(const ASymbolName: string;
  ADepth: Integer): TArray<TImpactLevel>;
function GetClassSurface(const AQName: string;
  AIncludeImpl, AAllVisibility: Boolean): TArray<TSurfaceLine>;
function GetSymbolSlice(const AQName: string): TArray<TSliceChunk>;
```

New records in `DRagLint.Core.Model.pas`:
```pascal
TImpactLevel = record
  Depth:      Integer;
  CallerCount: Integer;
  UnitCount:  Integer;
  Categories: TArray<string>;  // 'form', 'frame', 'service', 'test', 'other'
end;

TSurfaceLine = record
  Kind:      string;   // 'class-decl', 'method-sig', 'property', 'field', 'end'
  Text:      string;   // verbatim source line(s)
  StartLine: Integer;
  EndLine:   Integer;
end;

TSliceChunk = record
  Kind:      string;   // 'unit-header', 'class-decl', 'impl-method', 'unit-trailer'
  Text:      string;
  StartLine: Integer;
  EndLine:   Integer;
end;
```

## 5. Implementation notes

- `surface` and `slice` read the source file by line range (existing files table records
  the path). Source must be ASCII per project rules; no encoding negotiation needed.
- `impact` uses recursive SQL via SQLite WITH RECURSIVE CTE, capped at the user's depth
  to prevent runaway on cyclic call graphs. Pre-prepare in `PrepareStatements`.
- `find-callers --context N` reuses the existing caller iteration, with a per-row
  file-read step. Cache the most recent N files to avoid re-reading on every row.

## 6. Categorization heuristic for `impact`

The "Touches: 3 forms, 2 frames..." line uses simple symbol-kind + name heuristics:

| Category | Detection |
|---|---|
| Form | qname contains `T*Form` AND unit imports `Vcl.Forms` |
| Frame | qname contains `T*Frame` AND unit imports `Vcl.Forms` |
| Service | unit name contains `Service` AND has a `class procedure` `Start`/`Stop` |
| Test | unit name starts with `TEST_` or class has `[Test]` attribute or `published` test methods |
| Other | default |

v0.18 may add finer categories. For v0.17, "Other" is a fine bucket.

## 7. Consumer surfaces

### CLI

```
drag-lint impact --qname Foo.TBar.Baz [--depth 3] [--format text|json]
drag-lint surface --qname Foo.TBar [--include-impl] [--all-visibility] [--format text|json]
drag-lint slice --qname Foo.TBar [--format text|json]
drag-lint query find-callers --name Baz [--context 5]
```

### MCP

Three new tools matching the CLI:
- `get_impact` — `{qname, depth?}`
- `get_surface` — `{qname, include_impl?, all_visibility?}`
- `get_slice` — `{qname}`

The existing `find_callers` MCP tool gains a `context` integer arg (default 0).

### LSP

No new LSP capabilities in v0.17. Hover stays as v0.16. (v0.20 will add completion
that consumes `surface` output.)

## 8. Stop criteria

1. `drag-lint impact --qname Docs.TDocDemo.GetBaz --depth 2` on the self-corpus or
   Micronite ORM3 prints a multi-level caller summary with non-zero counts at each
   depth level.
2. `drag-lint surface --qname Vcl.Controls.TWinControl` on the RTL+VCL index prints
   the public interface of TWinControl without its 5000-line implementation.
3. `drag-lint slice --qname Docs.TDocDemo` on `tests/fixtures/Docs.pas` prints the
   unit header + TDocDemo class + only its impl methods (DoOne/DoTwo/DoThree/OldProc/
   GetBaz/Add bodies), skipping `end.` of unit only after them.
4. `drag-lint query find-callers --name DoBar --context 3` on the smoke fixture prints
   each caller with 3 lines of surrounding code.
5. Three new MCP tools advertised in `tools/list` and respond correctly.
6. Index time on DevExpress within 0% of v0.16 (no index-path changes).
7. T1-T13 from v0.16 still pass.

## 9. Out of scope for v0.17 (named, deferred)

- **Populating `refs.symbol_id` at index time** to make `impact` precision-perfect.
  Currently `impact` over-fans on generic names. Deferred to v0.22+ (Slice C —
  Graphify-inspired refs precision).
- **`drag-lint hotspots`** (degree centrality ranking). v0.22.
- **Inheritance/override walk in `impact`**. v0.22.
- **Context bundles** (`drag-lint context`). v0.18 — headline.

## 10. Versioning + push policy

Branch `v0.17-blast-radius` off `v0.16-doc-extraction`. Local tag `v0.17.0-alpha` at
the release commit. Do not push — user reserves push authorization.
