# RESUME -- 2026-08-13 (session 17, autonomous stretch)

Supersedes `RESUME-2026-08-13e-loopzero-yadfot-and-autodoc.md`.

## Status

`main` = **`17e3fb1`**, **25 unpushed**. Battery **269/269 GREEN**.
`C:\Projects\YADF` on `autodoc-phaseC` at **`b65b2f9`**.
`C:\Projects\DataCopy` (Mercurial) at **`7b12ede24837`**; 3 modified files are
IDE artifacts (`.dsv`, `.dsk`), not work.

Pushing needs `git config http.postBuffer 524288000` + `http.version HTTP/1.1`.

## Counts

| Project | start of day | now | note |
|---|---|---|---|
| YADF | 12 | **6** | 0 errors, **0 warnings** |
| YADFOT | 35 | 14 | 6 doc-drift are the shared-unit block |
| YADFSetup | 24 | 15 | same |
| DataCopy | 107 | **48** | **0 errors** |

## THE BIG ONE: autodoc non-idempotency is CLOSED

`INBOX-autodoc-not-idempotent-on-yadf` (54 pending edits after a full apply,
open since 2026-08-11) is resolved. Both projects now converge:

    document --project YADF     --apply -> 12 edits ; 2nd pass "nothing to document"
    document --project DataCopy --apply -> 48 edits ; 2nd pass "nothing to document"

**It was one bug wearing three names.** The "unexplained" duplication, the
non-idempotency, and `INBOX-document-qname-second-apply-nests-block-on-stale-anchor`
are all ANCHORS GOING STALE MID-APPLY: each insert shifts the declarations below
it while the plan holds pre-insert line numbers, so `FindDocRegionAbove` (window
`[DeclLine-2, DeclLine-1]`, `AllowGap = 1`) finds nothing, `Existing.StartLine`
stays 0, and the duplicate guard is skipped FOR WANT OF A REGION -- falling
through to an unconditional insert, once per symbol.

Repaired in source: `YADF.Groups.pas` and `YADF.Options.pas` each carried FOUR
byte-identical `<remarks>` blocks above one declaration, `YADF.Tokens.pas` three
(78 lines, `60538e4`). DataCopy had a three-way doc MASH that was the source of
its only `error` (`7b12ede24837`).

**The underlying anchor bug is NOT fixed.** `a233d1d` only widened the
duplicate-insert guard past blank lines, which stops IDENTICAL blocks stacking.
When regenerated text DIFFERS there is no duplicate to recognise and the insert
still lands at a stale anchor. Real fix: re-resolve anchors as edits land, or
apply-then-reindex per file.

## Engine fixes shipped (all battery-green)

* `4a28a10` **try-except-swallowed keys on the EXCEPTION, not the sink's name.**
  The substring list had been patched twice before for the same reason.
* `968e7ce` **object-leak: an enclosing `try..except` hid the `try..finally`.**
  Probe-isolated -- the plan had this catalogued as "the guard is the NEXT
  statement", which is the WRONG cause.
* `17e3fb1` **try-except-swallowed accepts `exit(X)`** -- Task 9c's Result
  conversion in the spelling Delphi actually uses.
* `a233d1d` doc duplicate-insert guard (partial, see above).

Every one ships with a PAIRED GUARD fixture (the case that must still fire), because
each fix would otherwise pass by widening the rule into uselessness.

## NEXT SESSION -- in order

1. **Answer Q0 in `docs/QUESTIONS-2026-08-13-autonomous-session.md`.** It may
   save the whole per-project-segments build. Every remaining doc-drift finding
   across YADFOT/YADFSetup is a TRUNCATED line, and `TSharedFacts` already
   reconciles across projects WITHOUT project names (it uses
   `UnitInClosure`). Truncation is the only thing that breaks it. Exempting
   `dl:shared` units from truncation would converge the family with no new
   machinery. Segments remain better for ATTRIBUTION but are no longer needed
   for convergence.
2. **`used-before-assignment`** -- minimal repro now exists, 8 lines, no store:
   an `out` arg assigned in an `if` CONDITION does not reach the `ELSE` branch.
   `INBOX-used-before-assignment-out-arg-in-large-routine.md` eliminates four
   wrong hypotheses by test (not out-args-as-reads, not the store, not
   cross-unit, not routine size). 7 findings on DataCopy, 2 on YADFOT.
3. **The stale-anchor fix** (item above) -- it gates any wide `--apply`.
4. **DataCopy's remaining 48**: 7 used-before-assignment (FP, do not allow),
   5 unused-parameter, 3 each of const-casing / unused-public-symbol /
   local-field-prefix / sleep-in-vcl, and singles. Not yet triaged.

## Traps paid for THIS stretch

* **`allow` writes to the file:line you give it, and will happily mark the wrong
  file.** I mapped a routine list to filenames wrongly and marked
  `uFileUtils.pas:539` instead of `uZeissRoutines.pas:539`.
  `review-marker-unused` caught it. Verify the file, not just the line.
* **Edit a source file and doc-drift EXPLODES until you reindex** -- 53 -> 59 on
  DataCopy from one 4-line comment insert. Reindex before believing a count.
* **Backticks inside a `hg commit -m "..."` from bash are command-substituted**
  and silently eat the word. One commit message lost a word this way.
* **`Select-String '<rule>'` on `<rule>.pas` matches every finding** -- the
  FILENAME contains the rule name. Filter on `'] <rule>:'`.
* **A probe can fail to reproduce because the "control" case is also suppressed**
  -- my first used-before-assignment probe was silent everywhere because
  `Writeln(Err)` is a call argument, hence a possible-def. Make the control read
  the variable in a comparison.
* **DataCopy does NOT build headlessly**: msbuild F2613 `Spring.Logging` not
  found inside spring4d's own source. The empty-conditional edit there is real
  syntax verified only by the parser (0 errors, unchanged symbol counts). Needs
  an IDE build.
* Battery ~15 min. Do not rebuild the exe while it runs -- `run_exe_freshness`
  exists precisely to fail when the binary is older than its sources.
