> # CLOSED 2026-08-16 (session 22) -- FIXED. The indexer discarded include defines.
>
> `TIndexer` preprocessed via the 2-arg `Preprocess(Utf8, FProfile)` overload,
> whose `IncludeMode` is `'off'` -- an `{$I}` include is blanked AND its
> `{$DEFINE}`s discarded. Now passes `'defines-only'` with `BaseDir` = the unit's
> own directory (`DRagLint.Core.Indexer.pas`). The preprocessor already
> implemented this correctly (`ApplyIncludeDefines`); it was simply never asked.
>
> All three units, measured after the fix:
>
> | unit | before | after |
> |---|---|---|
> | `SsShlDlg.pas` | 0 symbols, 1 error | **404 symbols, 2068 refs, 0 errors** |
> | `StShlCtl.pas` | 0 symbols, 1 error | **1678 symbols, 11187 refs, 0 errors** |
> | `StShlDD.pas`  | 0 symbols, 1 error | **88 symbols, 517 refs, 0 errors** |
>
> The whole 27-file folder now indexes with **0 errors** (was 3).
>
> Test: `tests\preprocess\run_index_include_defines.ps1`. Its NEGATIVE control
> (`noinc.pas`, which includes nothing and must STILL fail) is the one that
> matters -- without it, "viainc parses" would also be achievable by seeding the
> define globally or by leaking one file's defines into the next.
>
> **The silent damage was the bigger half.** These three units were merely the
> visible case, because their dead branch contains a deliberate `!!` breaker.
> Every other unit taking feature defines from a shared `.inc` was indexing the
> WRONG BRANCH with no error at all. Any index built before this fix over such
> code is suspect and should be rebuilt.
>
> Original note follows.

# INBOX: three TurboPower ShellShock units fail to parse (2026-08-05)

Class: **unsupported** (parser/grammar gap). Found while indexing
`C:\Projects\tpshellshock\source` into the library index.

## Affected files

| file | reported position | what is at that position |
|---|---|---|
| `SsShlDlg.pas` | `(41,1)` | `unit SsShlDlg;` |
| `StShlCtl.pas` | `(40,1)` | `unit StShlCtl;` |
| `StShlDD.pas`  | `(37,1)` | `unit StShlDD;` |

Each yields `0 symbols, 0 refs, 1 errors` -- the whole unit is lost, so nothing
in them is queryable. The other 20 files in the same folder index cleanly.

## Self-contained repro

```
mkdir repro
copy C:\Projects\tpshellshock\source\StShlCtl.pas repro
copy C:\Projects\tpshellshock\source\SsDefine.inc repro
drag-lint index repro --db repro\t.sqlite
  -> StShlCtl.pas -> 0 symbols, 0 refs, 1 errors
     DIAG: StShlCtl.pas(40,1): parse error [ERROR]
```

Reproduces with only those two files present, so it is the file content, not
the surrounding folder or the size of the target DB.

## What it is NOT

The obvious hypothesis was the directive prologue. These three carry
`{$I+}` / `{$H+}` **before** the `unit` keyword, while `SsBase.pas` -- which
parses fine -- has only `{$I SsDefine.inc}` there. `{$I}` is ambiguous in Delphi
(include-file vs I/O-checking switch depending on the next character), so
mis-lexing `{$I+}` as an include of a file named `+` looked likely.

**That hypothesis is wrong.** A minimal unit:

```pascal
{$I+} {I/O Checking On}
unit IoPlusFirst;
interface
procedure Alpha;
implementation
procedure Alpha; begin end;
end.
```

indexes cleanly (`2 symbols, 0 errors`). So `{$I+}` ahead of `unit` is handled;
the real trigger is something else inside these three files and still needs
bisecting. Recording it here rather than guessing.

File facts, in case they matter: `StShlCtl.pas` is 270,385 bytes, no BOM, pure
7-bit ASCII. All three are shell-namespace units that lean heavily on
`{$IFDEF VER130}` / BCB conditional blocks near the top.

## Bisection Progress (2026-08-05, evening session)

Performed binary bisection on `StShlCtl.pas` (8238 lines) using the rebuilt
`drag-lint.exe`:
- Lines 1..8235 + end. -> **PASS** (parses clean)
- Lines 1..8237 + end. -> **PASS** (parses clean)
- Original file -> **FAIL** (parse error at 40:1)

The file structure around the problem area (finalization block):
```
Line 8233: finalization
Line 8234:   if NeedToUninitialize then
Line 8235:     OleUninitialize;
Line 8236: (blank)
Line 8237: end.
```

Hypothesis: The issue is **not** in the finalization block or the
initialization section. It likely involves a directive, conditional, or
construct between the `interface` and the main code that the preprocessor or
parser chokes on. The `interface` block has many `{$IFDEF VER130}` directives
and `{$HPPEMIT}` blocks that might be causing the issue.

The reported error position (40:1) is definitely where the parser's error node
surfaces, not the root cause -- the actual problem is earlier in the file.

## ROOT CAUSE FOUND 2026-08-16 -- `{$DEFINE}` in an `{$I}` include never reaches the unit

The bisection above was chasing the wrong thing, and its "1..8237 + `end.` PASSES"
result is a harness artifact (line 8238 is only the trailing newline, so that
variant was the whole file plus a duplicate `end.`). The trigger is in the
**prologue**, at lines 54-56:

```pascal
{$IFNDEF VERSION3}
  !! Error: This unit can only be compiled with Delphi 3 and above
{$ENDIF}
```

A deliberate compile-breaker. `VERSION3` is defined at `SsDefine.inc:106`, reached
through a nested chain (`{$IFNDEF VER80}` -> `VERSION2` -> `{$IFDEF VERSION2}` +
`{$IFNDEF VER90}` + `{$IFNDEF VER93}` -> `VERSION3`). drag-lint never records that
define, so the `{$IFNDEF VERSION3}` branch stays LIVE and `!!` is parsed as code.

**Correlation is 3-for-3 with no false positives:** `grep -ln '^\s*!!' *.pas` over
`tpshellshock\source` returns exactly `SsShlDlg.pas`, `StShlCtl.pas`, `StShlDD.pas`
-- precisely the three failing units. The other 20 files have no breaker.

### Proof

Injecting `{$DEFINE VERSION3}` into `StShlCtl.pas` ahead of the include turns
`0 symbols, 0 refs, 1 errors` into **`1622 symbols, 11053 refs, 0 errors`**.

### Minimal fixtures (measured, with positive controls)

| # | shape | result |
|---|---|---|
| C | nested `{$IFNDEF}`/`{$DEFINE}` chain **inline in the .pas** | **2 symbols, 0 errors** (POSITIVE CONTROL -- nested conditionals work) |
| D | ONE unguarded `{$DEFINE LVL3}` in an `{$I}` include | 0 symbols, **1 error** |
| F | same, include placed **after** `unit`/`interface` | 0 symbols, **1 error** (position is NOT the variable) |
| G | pre-`unit` include containing only a comment | **2 symbols, 0 errors** (a pre-unit `{$I}` is not itself fatal) |
| A | unguarded `{$DEFINE VERSION3}` at top of real `SsDefine.inc` | 0 symbols, **1 error** |

D is a 3-line repro. C and G are the controls that keep D honest: without them,
D failing proves nothing about includes specifically.

### Where it lives

`TIndexer` preprocesses via the **2-arg** `Preprocess(Utf8, FProfile)` at
`src\core\DRagLint.Core.Indexer.pas:828`. That overload is documented at
`src\preprocess\DRagLint.Preprocess.pas:74` as IncludeMode **`'off'`** -- *"includes
are simply blanked, their defines NOT applied"* (also `Preprocess.pas:544`,
`Preprocess.Types.pas:112`). Preprocessing is byte-length-preserving (blank to
spaces, LF kept -- the offset-identity invariant), so an include is **erased**, not
spliced.

`ApplyIncludeDefines` (`Preprocess.pas:348-367`) already implements the correct
behaviour -- it recurses with the **same** define dictionaries "so the child's
`{$DEFINE}`/`{$UNDEF}` are visible to the parent's later `{$IFDEF}`". It is simply
unreachable from the indexer: it is gated on `AIncludeMode = 'defines-only'`
(`Preprocess.pas:483-484`), and the only thing that ever sets that is the CLI flag
`--include-mode` (`DRagLint.CLI.pas:1090, 13383`). The engine exists; the indexer
never asks for it.

### Why this is much bigger than three units

The three ShellShock units are only the **visible** case, because their dead branch
contains a deliberate syntax error. Everywhere else the same bug is **silent**: a
unit whose feature defines come from a shared `.inc` -- the standard legacy Delphi
idiom -- simply gets the *wrong branch* indexed, with no error and no diagnostic.
Wrong symbols, wrong refs, full confidence. All 23 ShellShock units are indexed as
though `VERSION2/3/4` were undefined.

### Next steps

1. Decide whether the indexer should pass `IncludeMode = 'defines-only'` with
   `BaseDir` = the unit's directory (and `NearSearch`), and what it costs -- every
   `{$I}` becomes a file read + recursive scan per unit indexed.
2. Note the fail-open at `Preprocess.pas:356`: an unresolved include silently
   `Exit`s and applies nothing. Under `'defines-only'` that would reintroduce this
   exact bug for any include not on the search path, without saying so. It needs a
   diagnostic, not a silent skip.
3. Fixtures D (RED) + C and G (positive controls) go in `tests\preprocess`. Run
   them against the UNFIXED exe first: C and G must pass, D must fail.
4. Re-measure the three units after the fix -- expect `StShlCtl.pas` alone to go
   from 0 to ~1622 symbols / ~11053 refs.


