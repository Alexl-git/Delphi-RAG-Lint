> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21).** REFUTED 2026-08-16: `dynamic` indexes as local_var uParserGaps.VarNamedDynamic.dynamic : Integer, and the unit parses with no error.

# INBOX -- parser: a var entry named `Dynamic` (or `Virtual`) fails to parse unless it is FIRST in its `var` block

Filed 2026-08-01 from the drag-lint self-index. Class: **unsupported construct** (a grammar gap, not
staleness -- it reproduces on a freshly indexed 8-line file). Logged in
`stats/draglint-gaps.log`.

## How it surfaced

An incremental reindex of our own `src/doc` during Phase 3 T7:

```
drag-lint index C:\Projects\Delphi-RAG-lint\src\doc --db C:\Projects\.drag-lint\Delphi-RAG-lint.sqlite
  ...
  C:\Projects\Delphi-RAG-lint\src\doc\DRagLint.Doc.SymbolFacts.pas -> 259 symbols, 1543 refs, 1 errors
    DIAG: C:\Projects\Delphi-RAG-lint\src\doc\DRagLint.Doc.SymbolFacts.pas(1407,10): parse error [ERROR]
```

The real source at that site is `WalkSqlLiterals`' local var block:

```pascal
procedure WalkSqlLiterals(const N: TTSNode; const ASrc: TBytes; AReads, AWrites: TStringList);
var
  Text   : string ;
  Dynamic: Boolean;   // <-- the offender
  I      : Integer;
begin
```

## Minimal repro

```pascal
unit gap;
implementation
procedure P;
var
  Zed: Integer;
  Dynamic: Boolean;
begin
end;
end.
```

`drag-lint index gap.pas --db gap.sqlite` -> `1 errors`, `parse error [ERROR]`.

## What was bisected, and what it rules out

Each row is one 8-line unit differing only in its `var` block. `errors` is the count of
`parse error` lines the indexer printed.

| var block | errors | rules out |
| --- | --- | --- |
| `Dynamic: Boolean;` (alone / first) | 0 | the NAME alone is not the trigger |
| `Text: string;` (alone) | 0 | -- |
| `Text: string;` + `Dynamic: Boolean;` | **1** | -- |
| `Zed: string;` + `Dynamic: Boolean;` | **1** | the name `Text` is irrelevant |
| `Zed: Integer;` + `Dynamic: Boolean;` | **1** | the `string` TYPE is irrelevant |
| `Zed: AnsiString;` + `Dynamic: Boolean;` | **1** | -- |
| `Zed: string;` + `Dynamic: Integer;` | **1** | the `Boolean` type is irrelevant |
| `Dynamic: Boolean;` + `I: Integer;` | 0 | **position is the trigger, not adjacency** |
| `Zed: string;` + `Virtual: Boolean;` | **1** | generalises to another method directive |
| `Zed: string;` + `Message: Boolean;` | 0 | does NOT generalise to every directive |
| `Zed: string;` + `Dynamical: Boolean;` | 0 | it is the whole word, not a prefix |
| `Text: string;` + `Zed: Boolean;` | 0 | control -- the two-entry shape itself is fine |

Also confirmed irrelevant: the routine's parameter list (a parameterless `procedure P;` reproduces it
just as the real 4-parameter header does).

## Diagnosis

`dynamic` and `virtual` are method directives. Once a declaration in the block has completed, the
grammar appears to accept a directive in the following position and consumes `Dynamic` as one --
after which `: Boolean;` has nowhere to attach. In FIRST position there is no preceding declaration
for a directive to bind to, so the identifier is read as a name and the entry parses.

Both are perfectly legal Delphi identifiers in a `var` block: the compiler accepts our
`DRagLint.Doc.SymbolFacts.pas` as written, and has for as long as that routine has existed.

## Impact

- One `[ERROR]` per affected file on every index run, and the enclosing routine's symbols/refs are
  degraded at that point -- `WalkSqlLiterals` is in the SQL-facts analyzer, so what is lost is
  index quality for the very facts Phase 2 ships.
- It is silent unless someone reads the indexer's DIAG lines. This one had been printing on every
  self-index run and was only noticed because the reindex output was being read closely.
- Likely present in third-party corpora too: `Dynamic` is an unremarkable field/var name.

## Repro assets

The bisect fixtures were written to a scratch directory and not kept -- the table above is
reproducible from the minimal repro in a few seconds. The affected real file is tracked:
`src/doc/DRagLint.Doc.SymbolFacts.pas:1405-1409`.

Index/DB used: `C:\Projects\.drag-lint\Delphi-RAG-lint.sqlite`, exe
`third_party\dll-win64\drag-lint.exe` (1.2.1-alpha, main's build, staged 2026-07-29).
