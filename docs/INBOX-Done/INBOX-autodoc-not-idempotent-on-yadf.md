> **RETIRED to INBOX-Done/ on 2026-08-15.** CLOSED session 17: all three YADF projects reach a stable fixed point, and autodoc on this repo's own source now reports 'nothing to document' on a second pass. Guarded by run_doc_idempotent.ps1 / run_doc_p3_idempotency_sweep.ps1.
>
> Original note follows unchanged.

# INBOX: autodoc does not converge on YADF -- 54 pending edits after a full apply

> ## ROOT-CAUSED AND FIXED 2026-08-14. It was ONE trailing newline.
>
> `TTextEditApplier` splits an insert's `Text` on CRLF/LF and inserts each part
> as its own line (`Refactor.TextEdit:423`). `Merged` ended with a line break, so
> `Split` produced a trailing EMPTY part and **every replace wrote one blank line
> more than it deleted.**
>
> Measured on committed YADF at `b65b2f9`, ONE `document --project YADFOT --apply`:
>
> | | before | after |
> |---|---|---|
> | blank lines between block and its declaration | 1 | **2** |
> | `TYadfOptions` declaration line | 42 | 43 |
> | `YADF.Options.pas` | 1044 | 1046 lines |
>
> That one extra blank makes the damage PERMANENT and SELF-INFLICTED.
> `FindDocRegionAbove` associates through `DocRegionInGapWindow` with
> `AAllowGap = 1` -- window `[DeclLine-2, DeclLine-1]` -- so at a gap of 2 the
> block is invisible to its own declaration forever after. The next run finds no
> region, `Existing.StartLine` stays 0, the replace path is skipped, and control
> reaches the unconditional insert. A second block appears, the gap grows again,
> once per run. **No second project is needed.** The shared-unit case only makes
> the two blocks DIFFER, so the duplicate-insert guard cannot recognise them and
> the corruption becomes visible instead of merely stacking clones.
>
> **Fix:** strip trailing EOL from `Merged` at the single point where it is
> final, so the replace path and the fresh-insert path cannot diverge --
> `DRagLint.Doc.Document.pas`, right after `MergeInboundFacts`. Three lines.
>
> **Verified, same measurement:** one apply of 22 edits now leaves the file at
> 1044 lines, the declaration at 42, the gap at 1. The family then converges:
>
>     round 1: 44 edits, 0 new orphans
>     round 2:  0 edits  -> CONVERGED
>
> against 85 edits and a fresh orphan at round 2 before the fix. `lint-all`:
> YADF 6, YADFOT **14 -> 8**, YADFSetup **15 -> 10**.
>
> The one pre-existing orphan in committed `YADF.Options.pas` was repaired by
> hand (kept the superset: the summary from the orphan, the 7-caller union from
> the adjacent block). `doc-orphan-block` now reports 0 across the family.
>
> **This supersedes the three reopened diagnoses below.** `a233d1d`'s
> `CommentRunStartAbove` and the 2026-08-13 "widened guard" were both patches on
> the SYMPTOM -- they could only ever suppress the second insert, never stop the
> gap from growing. They are left in place as belt-and-braces.
>
> Still open, and NOT this bug:
> `docs\INBOX-shared-unit-empty-render-deletes-block.md` (a narrow project emits
> a pure deletion when its own render is empty).


> ## REOPENED 2026-08-14. The convergence gate is GREEN OVER CORRUPTED SOURCE.
>
> The 2026-08-13 close-out ("both projects converge, 2nd pass = nothing to
> document") is true and is **not sufficient evidence**. Measured today:
>
> * At `b65b2f9` -- the commit whose message says autodoc CONVERGES -- pass B is
>   green on all three projects AND `YADF.Options.pas` already carries a stacked
>   orphan pair at lines **486/499**. The prior session's repair missed it.
> * A wide apply across the family (YADF 16 edits, YADFOT 20, YADFSetup refused
>   42, then `--reindex` rounds of 2 and 4) produced **three** stacked pairs,
>   including a differing-content one at 494/507/519. Pass B was green over that
>   too: `nothing to document` on all three.
> * Reverted with `git checkout -- '*.pas'`; YADF is back at `b65b2f9`.
>
> **Why the gate cannot see it.** A duplicated block is an ORPHAN -- no
> declaration sits within `AllowGap` of it -- so `FindDocRegionAbove` never
> associates it with anything. The documenter neither rewrites nor removes it and
> truthfully reports nothing to do. Convergence and correctness are independent
> here, and only convergence was ever measured.
>
> **What is missing is a DETECTOR, and nothing in the 269-test battery is one.**
> The rule is cheap: between two consecutive `drag-lint:auto BEGIN` markers there
> must be at least one line that is neither blank nor a comment. That single
> predicate finds all four pairs above, and would have failed the 2026-08-13
> close-out. Until it exists, "pass B = 0" must not be quoted as done.
>
> **Line-count neutrality is necessary, not sufficient.** All 29 edits in the
> first dry-run plan were verified same-line-count replacements (delete N, insert
> N), which is why the first apply was judged safe. The corruption still happened,
> because the CASCADE generates edits that plan was never checked against: each
> project's apply rewrites shared source, so the next project plans against an
> index describing a file that no longer exists. YADFSetup's freshness guard
> caught this and refused 42 edits; **YADFOT's did not**, and that asymmetry is
> the sharpest lead into the anchor bug -- one path validates the declaration line
> against the index and the other does not.
>
> **A REINDEX BEFORE EVERY APPLY IS NOT SUFFICIENT.** Tested directly, because
> it was the obvious fix and it is wrong. Sequence: rebuild project DB through
> the manifest -> apply -> rebuild -> apply, with the new `doc-orphan-block`
> detector run over all 16 files after every single step.
>
>     round 1  YADF 16 applied / 0 refused   -> orphans 0
>              YADFOT 22 applied / 2 refused -> orphans 0
>              YADFSetup 47 applied / 39 refused -> orphans 0
>     round 2  3 edits total                 -> orphans 1   <-- TRIPWIRE
>
> So the staleness that matters is INTRA-apply, within one project's own plan,
> exactly as the 2026-08-13 root cause said. Cross-project cascade makes it worse
> but is not the cause. (The freshness guard is meanwhile doing real work -- it
> refused 2 and then 39 edits rather than writing them at stale anchors.)
>
> **AND THE DUPLICATE IS BYTE-IDENTICAL, which `a233d1d` claims to cover.**
> Round 2 produced this above `TYadfOptions = record` in YADF.Options.pas:
>
>     /// <remarks> ... auto BEGIN ... Used by: <7 entries> ... auto END ... </remarks>
>     <blank>
>     <blank>
>     /// <remarks> ... auto BEGIN ... Used by: <the SAME 7 entries> ... auto END ... </remarks>
>     <blank>
>     TYadfOptions = record
>
> Two identical blocks. `CommentRunStartAbove` + `CommentLinesContain`
> (`DRagLint.Doc.Document.pas:1173`) exists precisely to suppress this and did
> not. That narrows the fix a long way, because only two things can explain it:
>
> 1. `Src` is the file as read at PLAN time, while the duplicate was created by
>    an EARLIER edit in the SAME apply -- so the guard compares against text that
>    does not yet contain the block it is meant to notice; or
> 2. the earlier edit left the gap at TWO blank lines, so `FindDocRegionAbove`
>    (window `[DeclLine-2, DeclLine-1]`, `AllowGap=1`) failed to associate,
>    `Existing.StartLine` stayed 0, the replace path was skipped, and control
>    reached the bare `tekInsertLines` at `:1184`.
>
> Both point at the same fix and it is not a wider guard: **re-read the buffer,
> or re-resolve the anchor, as each edit lands.** A guard that reasons about
> pre-edit text cannot see damage done after it was read.
>
> Reproduce: YADF at `b65b2f9`, rebuild the three DBs via
> `index --all --only <P> --rebuild`, then apply each project in turn, running
> `lint <file>` for `doc-orphan-block` after every step. It shows up in round 2.
>
> **Do not run a multi-project `document --apply` until this is fixed.** Single
> project, then reindex, then the detector, survives exactly one round.
>
> Also settled today: **the `Covered by:` oscillation below is DORMANT, not
> fixed.** The string appears in no YADF `.pas` before or after a full
> apply+reindex cycle. It is not being computed at all, so nothing proves the
> oscillation would not return if it were.


> ## ROOT-CAUSED 2026-08-13. The mechanism is a STALE ANCHOR, and the damage was
> already in committed source.
>
> ### What the source actually looked like
>
> `YADF.Groups.pas` carried **FOUR byte-identical `<remarks>` blocks** stacked
> above `TGroup = class`, each separated from the next by two blank lines.
> `YADF.Options.pas` the same. `YADF.Tokens.pas` had three, of which two were
> identical and the third was the YADFOT-scoped variant (no `YadfMain` in
> `Used in units:`). A dry run proposed adding yet another
> (`insert after line 64`), so the growth was still live.
>
> `git blame` puts every one of those lines on `bc4bb02` -- ONE apply, the
> "regenerate shared-unit facts" run. Before it, `TGroup`'s block was single and
> correctly ADJACENT (`</remarks>` on line 38, `TGroup = class` on 39).
>
> ### Why one apply produced four blocks
>
> The anchor went stale DURING the apply. Once a block is inserted, every
> declaration below it shifts down, but the plan was computed against
> pre-insert line numbers. `FindDocRegionAbove` then looks for an existing
> region in `DocRegionInGapWindow(EndLine, DeclLine, AllowGap)` with
> `AllowGap = 1` -- window `[DeclLine-2, DeclLine-1]`. Off by more than one
> line, nothing is found, `Existing.StartLine` stays 0, the
> `CommentLinesContain` duplicate guard is skipped **for want of a region**, and
> control reaches the unconditional insert. Repeat per symbol.
>
> **This is the same defect as
> `INBOX-document-qname-second-apply-nests-block-on-stale-anchor.md`** -- there
> the staleness comes from a previous `--apply`, here from earlier edits in the
> same plan. One fix should close both.
>
> ### What was done 2026-08-13
>
> 1. **Guard widened** (`CommentRunStartAbove`, `DRagLint.Doc.Document.pas`):
>    the duplicate-insert check now scans the whole comment/blank run above the
>    declaration instead of only the association window. Deliberately NOT a
>    change to `AllowGap`, which is shared by the indexer, harvest, facts and
>    strip -- widening that would change which declaration a comment BELONGS to
>    everywhere at once. The guard can only suppress an insert; it cannot move,
>    retarget or delete a comment.
>    **Limit, measured:** it stops IDENTICAL blocks stacking. It does NOT help
>    when the regenerated text differs from the block already present, because
>    then there is no duplicate to recognise -- the insert is "new" content
>    landing at a stale anchor. That case still needs the anchor fixed.
> 2. **Committed source repaired**: the chains were collapsed to one block each,
>    adjacent to their declaration. For the Tokens.pas chain, whose blocks
>    differed, the SUPERSET (`... YadfMain`) was kept, per the union rule for
>    shared units. A chain whose blocks differ is not mechanically collapsible
>    and the repair script refuses it rather than guessing.
>
> ### Still open -- the real fix
>
> `--apply` must not plan against line numbers it has already invalidated.
> Either re-resolve each anchor against the current buffer as edits land, or
> apply-then-reindex per file. This is the freshness rule from
> `specs/2026-08-13-db-authority-and-freshness.md` ("any DB/source mismatch ->
> complete reindex") applied WITHIN a single apply.
>
> Until that lands, treat a multi-symbol `document --apply` as unsafe on files
> that already carry managed blocks, and re-run the duplicate detector after
> any wide apply.

Measured 2026-08-11 by the deferred YADF pipeline run (engine 1.2.2-alpha,
`C:\TEMP\claude\yadf_report-20260811-164822.txt`).

## The gate that failed

The pipeline is: full reindex -> lint baseline -> `document --apply` -> full
reindex -> **dry-run pass B** -> lint-all. Pass B must report **0** pending
edits; a second dry run over freshly-documented, freshly-indexed source should
find nothing left to write. That is the reproducibility gate, and on drag-lint's
own source it has held at 0 on every run since the ordering fix.

On YADF it does not:

```
autodoc edits applied : 182 across 12 file(s)
PASS-B PENDING EDITS  : 54 across 5 file(s)     <-- must be 0
```

| file | pending edits |
|---|---|
| YADF.Options.pas  | 28 |
| YADF.LineScan.pas | 16 |
| YADF.Layout.pas   | 4 (listed twice -- see below) |
| YADF.Tokens.pas   | 2 |

`YADF.Layout.pas` appears TWICE in the per-file sweep, which means the walk sees
two files of that name. Worth resolving before reading anything into its count.

## DIAGNOSED 2026-08-11: the `Covered by:` fact OSCILLATES across a reindex

The disagreement is exactly one line per affected declaration:

```
/// Covered by: TestFormatSourceStillFormats        <-- in the file
                                                    <-- absent from the regenerated block
```

Established by measurement, in this order:

1. **The pass is self-consistent without a reindex.** On `YADF.Tokens.pas`:
   dry-run says 2 edits -> `--apply` -> dry-run again says **"nothing to
   document"**, and `grep -c 'Covered by'` is **0**. So the planner and the
   writer agree.
2. **A reindex flips it back.** After a `--rebuild` and a second apply sweep,
   `YADF.Tokens.pas` contains `Covered by:` **again** (grep = 1) and is once more
   in the pending list. The line is removed, then re-added, then removed.
3. **Two full apply+rebuild cycles left the count unchanged: 54 pending across 5
   files, both times.** Not converging slowly -- not converging at all.
4. The five files that still hold `Covered by:` are exactly the five that do not
   converge.

**Refuted along the way** (recorded so it is not re-tried): it is NOT about
overloads. `YADF.LineScan.pas`, `YADF.Options.pas`, `YADF.OptionsFrame.pas` and
`YADF.Tokens.pas` carry zero `Overload N of M` markers and still fail, while
`YADF.Guard.pas` has two overloads and converges cleanly.

**Where to look.** `Covered by:` names TEST routines
(`TestFormatSourceStillFormats`, `TestDuplicationToleranceAndReason`). YADF's
tests live in `YADFOT.dproj`, which since the 2026-08-09 per-project split is a
**separate database** (`YADFOT.sqlite`). So the fact needs cross-project
visibility that the `YADF` index does not have -- yet it is sometimes derivable
and sometimes not, which is precisely the shape of an oscillation. The first
question to answer is: what makes it derivable on one pass and not the next,
given the same two databases on disk?

A fact that cannot be computed from the configured index should be **preserved,
not stripped** -- deleting it destroys real information (which test covers this
routine) that nothing else in the corpus records. Compare the `AUTO_TYPE`
ownership marker, which exists for exactly this reason.

## Why it matters

`document --apply` REWRITES SOURCE. A pass that does not converge means running
it twice produces different files, so "documented" is not a fixed point and no
run can be called finished. It also explains the residual `doc-drift` count:
lint-all still reports **151 doc-drift** findings immediately after a full apply,
which should be near zero if the writer and the checker agreed.

That is the same writer-vs-checker disagreement class that produced the 514
false doc-drift findings earlier (checker regenerating without `<seealso>`), the
`AUTO_TYPE` ownership marker, and the implementation-section scope fix. The four
things they must agree on are OPTIONS, OWNERSHIP, SCOPE and PROTECTION -- start
by asking which of those differs on these five files.

## Lint effect of the run, for the record

| | before autodoc | after |
|---|---|---|
| lint-all | 1,133 | **1,072** |
| errors | 0 | 0 |
| warnings | 368 | 307 |
| info | 705 | 705 |
| hints | 60 | 60 |

The entire -61 is in `warning`; info/hint are unchanged. Top rules after:
`inherited-bare` 183, `doc-drift` 151, `case-magic-numbers` 106,
`large-magic-number` 102, `local-var-casing` 91, `doc-param-no-description` 78.

`inherited-bare` at 183 on a 16-file project is the single largest class and has
never been sampled -- do that before believing it, per the standing rule that a
big number is a hypothesis until twelve of its findings have been read.

## Second, unrelated defect visible in the same output

`lint-all` prints its report path as `report: C:lint-report-20260811.txt` -- the
backslash after the drive letter is missing. Either the file is being written to
the process's current directory on drive C (a CWD-relative path that only looks
absolute), or the banner is mis-formatting a correct path. Both are worth one
look; the first silently scatters reports.

## Reproduce

`C:\TEMP\claude\yadf_pipeline.sh` (run-stamped; records YADF's branch and HEAD,
and prints the exact `git checkout -- .` needed to undo the apply). YADF was on
branch `autodoc-phaseC` at `14ab163`.
