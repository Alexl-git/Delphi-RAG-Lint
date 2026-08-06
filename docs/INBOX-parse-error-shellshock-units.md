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

## Suggested next steps

1. Bisect the **prologue** (lines 1..60) more carefully, focusing on:
   - The include directive (`{$I SsDefine.inc}`)
   - The preprocessor directives (`{$IFDEF}`, `{$IF}`, etc.)
   - The `{$HPPEMIT}` blocks in the interface section

2. Compare with `SsBase.pas` (which parses fine) to see what's different
   in the prologue or early code structure

3. Add a minimal repro fixture to `tests\preprocess` once identified


