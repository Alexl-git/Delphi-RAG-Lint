# OWED -- audit every store-backed fix path for the stale-position guard

> **AUDIT DONE 2026-08-16. The note was ~80% stale; the residual was ONE line.**
>
> Re-measured before coding, and most of what this note asks for already exists:
>
> * **"`tekReplaceInLine` clamps EndCol but not Col, so a stale column silently
>   APPENDS"** -- no longer true. `ReplaceEditIsValid`
>   (`Refactor.TextEdit.pas:260`) REJECTS an edit whose `Col` is past
>   end-of-line, with the comment *"past end-of-line: reject, never append"*.
> * **"one shared assertion at the edit-emitting boundary"** -- exists, and is
>   the ONE implementation this note asks for: `TTextEdit.ExpectLine` /
>   `ExpectText`, validated by `AnchorIsValid` + `ReplaceEditIsValid` inside
>   `TTextEditApplier.Apply`, which reports rejects through `ASkippedEdits` and
>   does not rewrite (or `.bak`) a file whose every edit was refused.
> * **"`doc-drift` and `missing-doc` resolve by (file, line) with NO
>   verification"** -- false. `StampAnchor` (`Doc.Document.pas:503`) stamps the
>   declaration line + symbol name, and the repair pair share one anchor
>   deliberately so a stale pair drops together and cannot half-apply.
>
> **The one real gap -- and it is NOT a live defect.** Of the FOUR edit sites in
> `Doc.Document.pas`, `StampAnchor` was called at three (1157 delete-half, 1165
> insert-half, 1250 fresh insert) and NOT at the fourth -- line 1074, *"the ONE
> place the engine emits a pure deletion"*. Found by counting:
> `query find-callers --name StampAnchor` -> 3, `tekDeleteLines|tekInsertLines`
> -> 4.
>
> **I then tried to build a guard for it and the guard passed WITHOUT the fix**,
> so I measured instead of assuming. With the stamp removed and the index
> deliberately stale (3 lines inserted above the declaration, no reindex), ALL
> THREE entry points already refuse, never reaching the branch:
>
> | entry point | stale result |
> |---|---|
> | `document --unit` | `nothing to document` |
> | `document --qname` | `up to date (no change)` |
> | `lint-all --fix --apply` | `no fixable findings` |
>
> File byte-identical in every case. The reason: `Existing` is recomputed from
> the **current file text**, so a store line that no longer holds the
> declaration yields no engine-owned region and therefore no edit at all. The
> store coordinate is an anchor to search near, not a span to delete blindly --
> which is the property this whole note assumed was missing.
>
> The stamp was added anyway, for consistency with the other three sites and as
> defence against a future caller that does resolve a span from store
> coordinates. **No regression test ships with it**, deliberately: an assertion
> that "the stale case is refused" is green either way, and a vacuous guard is
> worse than none -- it advertises coverage that does not exist.
>
> **Retire this note.** Nothing in it is actionable; the residual is recorded in
> the code comment at the site.


Extracted 2026-08-15 from `INBOX-naming-autofix-corrupts-source-on-stale-index.md`
as that note was retired to `INBOX-Done/`. **The note's headline defect IS fixed;
this residual is not, and would have been lost with it.**

## What was fixed, and what that proves

The naming/rename autofix used to apply DB-recorded `(line, col)` positions to a
file that had changed since indexing, writing at coordinates that addressed
unrelated text. Field result: `else` became `elseGlyActive`, exit code 0, silent
source corruption. Fixed in v0.82 -- `DRagLint.Refactor.Rename.pas:374` refuses
the edit unless the text at the recorded span still matches the identifier being
renamed, and `DRagLint.Refactor.NamingFix` counts the rejected sites so a skip is
visible. Guarded by `tests\autofix\run_fix_stale_index_guard.ps1`.

**The general lesson was never applied.** Staleness is normal -- an index is
always a snapshot -- so the defect is not the staleness, it is APPLYING AN EDIT
WITHOUT VERIFYING THE TARGET. Any writer that resolves its target from the store
has the same exposure, and only one of them was hardened.

## What to audit

Named in the original note as equally exposed, both resolving declarations by
(file, line) from the store:

* **`doc-drift`** -- the managed-facts-block rewrite path.
* **`missing-doc`** -- the fresh-comment insert path.

Add to that list anything else reaching `TDocumenter.BuildFor` or emitting a
`TTextEdit` from store coordinates. Note `TTextEditApplier`'s `tekReplaceInLine`
clamps `EndCol` but NOT `Col`, so a column past end-of-line silently APPENDS
rather than failing -- which is why the naming bug produced glued identifiers
instead of an exception.

## Why this is not merely theoretical for the doc paths

The doc writer runs `--apply` over whole projects routinely (212 edits on this
repo's own source in one session), and its own INBOX history already contains two
destructive incidents from writing to the wrong place: the stale-anchor bug (a
trailing newline pushed every managed block one line out of association, and each
run added another orphan) and the shared-unit deletion. Both were position
errors. A verification step at the point of writing would have caught either.

## Suggested shape

One shared assertion at the edit-emitting boundary rather than per rule: given a
`TTextEdit` derived from store coordinates, require that the current file text at
that span still matches what the edit expects to replace, and count + report
rejects rather than writing. That is what the rename path now does; the point is
to have ONE implementation of it, since this defect class has now been fixed
per-command twice (`ownRoots`, then `exclude_paths`) and per-rule once.

## Guard

A fixture that indexes a file, THEN inserts lines above the target, THEN runs
`document --apply` / `lint-all --fix --apply`, asserting the file is either
correctly modified or untouched -- never corrupted, and never a non-zero edit
count with a broken result. `run_fix_stale_index_guard.ps1`'s load-bearing trick
is worth copying: for a re-casing fix it asserts the whole file LOWER-CASED is
byte-identical before and after, which catches a same-length wrong-target write
that would otherwise compile and ship.
