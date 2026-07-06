# PP-Task-11: Measured IFDEF-Resolution Gain

Recorded 2026-07-06 as part of PP-Task-11 (finalize verbs + full battery +
measure). Full method and battery results are in `.superpowers/sdd/pp-task-11-report.md`;
this file is the durable measurement record referenced by the task-11 commit.

## Method

Two independent A/B index runs, each comparing preprocess ON (default,
per-config `{$IFDEF}` resolution) against `--no-preprocess` (raw all-branch
parsing), using the STAGED exe `third_party\dll-win64\drag-lint.exe`, from a
neutral CWD (`C:\TEMP\pp11-measure`), into throwaway scratch databases (never
the user's real indexes).

## Measurement A: drag-lint's own src/ tree

Indexed `C:\Projects\Delphi-RAG-lint\src` (124 files) twice:

| Run                    | Files | Symbols | Refs  | Parse errors |
|------------------------|-------|---------|-------|---------------|
| preprocess ON (default)| 124   | 10872   | 56007 | 9             |
| `--no-preprocess`       | 124   | 10872   | 56007 | 9             |

Delta: 0. Both runs produced byte-identical symbol/ref/error totals.

Why: a grep of `src/**/*.pas` for real `{$IF`/`{$ELSE`/`{$ENDIF` directives
(excluding comments and string literals that merely mention "{$IFDEF}" in
prose) found exactly ONE active conditional block in the whole tree --
`SizeGuardCheck` in `src/cli/DRagLint.CLI.pas`:

```
{$IFNDEF WIN64}
Is32Bit:= True;
{$ELSE}
Is32Bit:= AForce32;
{$ENDIF}
```

Both branches are well-formed (no dangling begin/end, no cross-branch brace
mismatch), so raw all-branch parsing never had a parse-error problem there to
begin with -- there is nothing for the preprocessor to fix in this file. The
9 pre-existing parse errors seen in BOTH runs (7 in DRagLint.CLI.pas, 1 each
in DragLint.Plugin.AutoComplete.pas and DragLint.Plugin.Editor.pas, tagged
`[kGt]`) are unrelated generics-parsing noise, not `{$IFDEF}`-caused -- they
reproduce identically with preprocessing OFF, so the preprocessor correctly
leaves them alone rather than masking or amplifying them.

Conclusion: drag-lint's own source is not representative IFDEF-heavy code --
the milestone's target failure class (a conditional branch with unbalanced
begin/end that only breaks the OTHER platform's parse) does not occur here.
A zero delta on this corpus is the honest, expected result, not a sign the
preprocessor is ineffective.

## Measurement B: the IFDEF-heavy fixture (platform_heavy.pas)

`tests\preprocess\fixtures\platform_heavy.pas` (built for the PP-Task-8 gate)
is the representative case: its POSIX branch has a dangling `begin` with no
matching `end`, so a raw all-branch parse of the WHOLE file genuinely trips
the grammar, while a Win64-profile preprocess blanks the inactive POSIX
branch before parsing and removes the imbalance.

Indexed the fixture alone (copied to a scratch dir, not the tests/ tree)
twice:

| Run                    | Files | Symbols | Refs | Parse errors |
|------------------------|-------|---------|------|---------------|
| preprocess ON (Win64)  | 1     | 4       | 3    | 0             |
| `--no-preprocess`       | 1     | 5       | 5    | 1             |

Delta: 1 -> 0 (matches the PP-Task-8 gate result independently reproduced
here). The single raw-mode error is the dangling `begin` inside the inactive
`{$IFDEF POSIX}` block; preprocess-ON blanks that whole branch (Win64 profile
does not define POSIX) before the parser ever sees it.

Per-config accuracy (not just fewer errors) also confirmed via `query`
against the preprocess-ON database:
- `WinOnlyProc` (declared under `{$IFDEF MSWINDOWS}`) -- PRESENT, 1 exact match.
- `PosixOnlyProc` (declared under `{$IFDEF POSIX}`) -- ABSENT, 0 matches
  (exit code 1), because the Win64 profile does not define POSIX so that
  branch is blanked rather than indexed.

## Summary

- The `{$IFDEF}`-cross-branch parse-failure class the preprocessor targets is
  real and fixed: 1 error -> 0 on the purpose-built fixture that exercises it,
  reproduced independently of the PP-Task-8 test harness.
- drag-lint's own `src/` tree happens to have only one (well-formed) active
  conditional block, so it shows a 0 -> 0 delta -- an honest measurement, not
  a gap in the port. The gain is real but was never going to show up on code
  that wasn't broken by IFDEFs in the first place.
- Both A/B runs used the STAGED win64 exe from a neutral CWD into scratch
  databases under `C:\TEMP\pp11-measure`; no production/user database was
  touched or modified.
