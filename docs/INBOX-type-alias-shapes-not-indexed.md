# INBOX -- four type-declaration shapes are never indexed

Filed 2026-08-02. Found while verifying converter fixes 2.1 / 2.11 on the merged
`feat/autodoc-phase3` build. **Not a regression** -- reproduced identically on
three separate binaries (see below).

Class: **unsupported construct** (emitter gap, same family as 2.1 and 2.11).

## Reproducer

`AliasShapes.pas` -- ten type declarations, one unit:

```pascal
unit AliasShapes;

interface

type
  TAliasIdent   = Integer;
  TAliasStr     = string;
  TAliasBool    = Boolean;
  TAliasPointer = Pointer;
  TStrongStr    = type string;
  TStrongInt    = type Integer;
  TRange        = 1..10;
  TEnum         = (eA, eB);
  TArr          = array[0..3] of Byte;
  TSetOf        = set of Byte;

implementation

end.
```

```
drag-lint index <dir> --db a.sqlite
drag-lint query --name <T> --db a.sqlite --json
```

Indexer reports `Files: 1, Symbols: 9`. Expected 11 -- one `unit` symbol plus
ten types. Four types produce NO row.

## Expected vs actual

| declaration | shape | indexed? |
|---|---|---|
| `TAliasIdent = Integer;` | alias to an identifier | yes |
| `TAliasBool = Boolean;` | alias to an identifier | yes |
| `TAliasPointer = Pointer;` | alias to an identifier | yes |
| `TStrongStr = type string;` | strong alias, keyword target | yes (2.11) |
| `TStrongInt = type Integer;` | strong alias, identifier target | yes (2.11) |
| `TEnum = (eA, eB);` | enum | yes |
| **`TAliasStr = string;`** | **plain alias, KEYWORD target** | **NO** |
| **`TRange = 1..10;`** | **subrange** | **NO** |
| **`TArr = array[0..3] of Byte;`** | **array type** | **NO** |
| **`TSetOf = set of Byte;`** | **set type** | **NO** |

## The asymmetry that pins the cause

`TStrongStr = type string;` **is** indexed while `TAliasStr = string;` is **not**
-- same target, differing only by the `type` keyword. That is the 2.11 fix's own
shape: `TryWalkStrongAlias` handles the keyword target because it takes the LAST
`type:` wrapper, whereas `TryWalkAlias` accepts only a direct `typeref` and a
keyword target (`(declString (kString))`) is not one. So the 2.11 fix closed the
strong form of this hole and left the plain form open.

Subrange / array / set are presumably the same class of miss: no emitter handler
claims their node, exactly as `declProcRef` had none before 2.1.

## Correction to LATEST-77

The LATEST-77 note in `docs/lint/BACKLOG.md` says 2.11's blind spot was only the
strong form, "which is exactly why plain aliases, subranges and enums were all
fine". Measured: **enums are fine, subranges are NOT, and plain aliases are fine
only when the target is an identifier.** Worth correcting in place, because it
is the sentence that would stop someone looking here.

## Reproduced on

Identical result -- `Symbols: 9`, same four missing -- from all three:

* `src/cli/Win64/Debug/drag-lint.exe` built from the merge commit `8f9e7b1`
* `wt-baseline-p3/src/cli/Win64/Debug/drag-lint.exe` built from `d1050a2` (pre-merge)
* `third_party/dll-win64/drag-lint.exe` as shipped, built from `main` `3b4a877`

So it predates both the merge and the four converter fixes.

## Why it matters

Whether these shapes SHOULD be indexed is a product call, not an obvious yes --
an array or set type alias has no class surface to offer. But `TAliasStr = string`
is the same kind of declaration as `TFileName = type string`, which 2.11 was
filed to fix precisely because the converter's Auto-Match needed it. A consumer
resolving a property's declared type hits the plain form just as often.

## Also noticed

`--force-reparse` is accepted (`DRagLint.CLI.pas:642`, also spelled `--no-skip`)
but appears in NO `--help` output. INBOX 2.3's grandfathering note tells existing
DBs to run it once; nothing in the tool's own help says it exists.
