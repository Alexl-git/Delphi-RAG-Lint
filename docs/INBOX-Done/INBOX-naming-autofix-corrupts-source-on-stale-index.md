> **RETIRED to INBOX-Done/ on 2026-08-15.** DEFECT WHOSE FIX IS SHIPPED and guarded by a green regression runner in the full battery.
>
> Original note follows unchanged.

# INBOX -- store-backed naming autofix CORRUPTS SOURCE when the index is stale

> **ALREADY FIXED (v0.82). This note's "Status: Not fixed" at the bottom is
> STALE -- verified 2026-08-14 (session 19) and corrected here rather than
> deleted, because a HIGH-severity "silent source corruption, not fixed" note is
> exactly what sends a future session chasing a solved problem, and its
> "Workaround" section talks a reader out of using a feature that works.**
>
> Suggested fix 1 -- the load-bearing one -- is implemented:
> `DRagLint.Refactor.Rename.pas:374` refuses the edit unless the text at the
> recorded span still matches the identifier being renamed, and falls back to a
> scan of the line before giving up:
>
> ```pascal
> if (ColIdx + OldLen > Length(LineStr))
>    or (not SameText(Copy(LineStr, ColIdx + 1, OldLen), Edit.OldName)) then
> ```
>
> Suggested fix 2 is implemented too: `DRagLint.Refactor.NamingFix` counts the
> rejected sites separately and documents it ("Non-zero means the store is stale
> for ..."), so a skip is visible rather than silent.
>
> The regression test asked for at the bottom of this note exists and passes:
> `tests\autofix\run_fix_stale_index_guard.ps1`, green in the full battery. It
> reproduces the exact field failure (`else` -> `elseGlyActive`) by indexing,
> then inserting a line above the use site WITHOUT reindexing. Its load-bearing
> assertion is the right one -- the whole file LOWER-CASED must be byte-identical
> before and after, since a pure re-casing fix may only change letter case. That
> catches a rename landing on a same-length identifier, which this note correctly
> identifies as the case that would otherwise have compiled and shipped.
>
> **Still worth doing, and NOT done:** this note's closing suggestion to audit
> *every* store-backed fix path for the same assumption. `doc-drift` and
> `missing-doc` resolve declarations by (file, line) and are equally exposed; only
> the naming/rename path got the guard. Filed forward as its own item rather than
> left implied here.

Found 2026-08-05 while running `local-var-casing` + `const-casing` autofixes against
`C:\Projects\DataCopy`. **Severity: high -- silent source corruption.**

## What happened

```
drag-lint lint --file uMainZeissCopy.pas --db <DataCopy> --fix \
                --config {"autofix":["local-var-casing","const-casing"]} --apply
-> autofix: applied 2 fix(es)
```

The build then failed:

```
uMainZeissCopy.pas(1242): E2029 'THEN' expected but identifier 'thenGlyActive' found
uMainZeissCopy.pas(1268): E2029 '.' expected but identifier 'elseGlyActive' found
```

Source lines 1242 / 1268 were `if not Err then` and `else`. The fixer appended the
identifier `GlyActive` directly onto the `then` / `else` KEYWORDS.

## Root cause: DB positions applied to a changed file, with no validation

`glyActive` is declared at **line 1023** and used at **line 1134**. The edits landed at
**1242 / 1268** -- nowhere near either site.

- index (`C:\Projects\DataCopy\drag-lint.sqlite`) last written **23:13:41**
- `uMainZeissCopy.pas` last modified **23:50** (unrelated edits inserted lines)

The naming fix path is store-backed: `BuildNamingFixEdits` resolves each symbol's
`(line, col)` from the SYMBOL STORE, not from the current file text. When the file has
changed since indexing, those coordinates point at unrelated text -- and the fixer writes
there anyway.

## The actual defect is the missing check, not the staleness

Staleness is normal and expected; an index is always a snapshot. The defect is that the
edit is applied **without verifying that the text at the recorded span is the identifier
being renamed**. One comparison would have turned silent corruption into a clean skip.

This is the same family as the `unused-local` autofix bug fixed in `41cb000` the same day:
a fixer that writes without verifying its target. Worth auditing every store-backed fix
path for the same assumption -- `doc-drift` and `missing-doc` also resolve decls by
(file, line) and are equally exposed.

Note this is ALSO why the corruption was caught at all: it happened to produce invalid
syntax. A rename landing on a different identifier of the same length would compile
cleanly and ship. **Exit code was 0.**

## Suggested fix

1. In `DRagLint.Refactor.NamingFix.BuildNamingFixEdits`, before emitting each
   `tekReplaceInLine`, read the current file line and assert
   `Copy(Line, Col, EndCol - Col) = <expected old identifier>` (case-insensitively --
   Delphi identifiers are). On mismatch: skip that edit and count it as skipped.
2. Surface the skip. A `--fix --explain` line ("N edits skipped: index stale for
   <file>") turns this into self-service; today it is invisible.
3. Cheap global guard: compare the store's recorded file mtime/sha against the file on
   disk before opening any store-backed fix path, and refuse with a clear
   "reindex <file> first" message rather than writing.

Recommendation 1 is the load-bearing one -- it makes the fixer correct regardless of
index freshness. 3 is a nicety.

## Regression test to add

Fixture + a runner that: indexes a file, THEN inserts blank lines above the target symbol,
THEN runs the naming fix. Assert the file is either correctly fixed or untouched -- never
corrupted, and never a non-zero edit count with a broken build.

## Workaround until fixed

Always reindex immediately before any store-backed `--fix` run:
`drag-lint index <dir> --db <db>`. Never run a naming autofix against a DB older than the
last edit to the target file.

## Status

Not fixed. The corrupted file was reverted (`hg revert`) and the DataCopy build restored to
green (both projects exit 0). No naming autofixes are currently applied to DataCopy.
