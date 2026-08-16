# RESUME -- 2026-08-15 (session 19, second stretch)

Supersedes `RESUME-2026-08-14-session19-lsp-and-prose-scanners.md`, which covers
the first stretch (VS Code LSP, the four prose scanners, cap-parity guard,
dangling-else). Read this one first; that one for the detail behind commits
`91c3e55`..`84be4c9`.

## Status

Branch **`session18-q0-orphan-anchor`**, **not pushed**. `main` at `17e3fb1`.

**START HERE: `docs/INBOX-INDEX.md`.** The INBOX was triaged from **108 notes to
59**; 49 were retired into `docs/INBOX-Done/`, each with a one-line banner saying
why. The index groups the remaining 59 into six priority bands with a "how to work
this list" section. That index, not this file, is the backlog.

### Triage bottom line

* **108 -> 59.** Nothing deleted; every retirement carries its reason.
* **What went:** 11 outbound REPLYs · 11 upstream tree-sitter status
  announcements · **21 defects already fixed AND guarded by a green runner** ·
  6 historical incident reports / superseded surveys.
* **The finding that matters:** roughly a fifth of the backlog was already done.
  Two of the scariest notes -- one HIGH-severity "silent source corruption,
  Status: Not fixed", one quoting 3/7/7 findings -- closed on **re-measurement
  alone, no code**. The first had been fixed in v0.82; the second is 1/1/1.
  So: **re-measure before coding** is now the first rule in the index.
* **What is genuinely left:** 59, of which 11 are features/designs rather than
  defects. The real defect backlog is ~48.

### Planning bottom line -- priority 1, in order

1. `group-E-dataflow-rules-are-majority-false` -- **section 1 done** (this
   stretch); `double-free` (42, sampled 6/6 false) is the next-largest wrong rule.
2. `remaining-raw-text-scans-read-comments-as-code` -- the last 3 of 9 instances.
3. `audit-store-backed-fix-paths-for-stale-positions` -- `doc-drift` and
   `missing-doc` write at store coordinates with NO verification.
4. `bare-except-anchor-defeats-a-hand-written-marker` -- take the `@hash` churn
   once, deliberately.
5. `returns-type-baseline-destroys-malformed-blocks` -- DESTRUCTIVE.
6. `shared-unit-empty-render-deletes-block` -- DESTRUCTIVE, **probably already
   closed**; rebuild the 3-unit fixture and CHECK IT IN this time.

## The two Fable reviews -- BOTH FINISHED, both acted on

Commissioned in parallel at the start of this stretch. Both delivered; neither is
outstanding.

**Review 1 -- full-tree audit for more instances of the prose-scanner family.**
Verdict: **the family is NINE instances, not four.** It found five beyond the four
already fixed, ranked them by user-visible harm, and -- as valuable -- **CLEARED
fifteen candidates with a reason each**, so nobody re-audits them. Its two
top-ranked findings (`ParseDprUses`, `ReadDeclLine`) are the two fixed in this
stretch; the other three are in the index at priority 1. It also identified that
`StripPasCommentsKeepLayout` already existed and was used correctly two units
away, which turned both fixes into one-line substitutions instead of new
scanners. Full table + cleared list:
`INBOX-remaining-raw-text-scans-read-comments-as-code.md`.

**Review 2 -- implementation plan for `overwrite-before-read`.** Delivered a plan
that was followed essentially as written, and its two most useful calls were
JUDGEMENT calls, not facts:
* **Fix the CHECK, not the CFG.** It read the `try..except` edge comments in
  `Cfg.pas`, recognised the edge as deliberate and depended upon by
  `used-before-assignment`, and pointed at `FreedInFinallyBlock` as the precedent
  for a rule-scoped syntactic guard. That is what stopped this becoming a change
  that perturbed every dataflow rule at once.
* **The sound predicate over the cheap one**, stated precisely enough to implement
  ("the handler MENTIONS the variable", covering read/free/re-assign without
  classifying them), plus the warning that the cheap version is the banned failure
  mode for this rule family.
It also measured the real tree-sitter child sequences with `dumpnode` rather than
assuming them, named the blast-radius suites (one of which, `run_flow_store_precision`,
did indeed need attention), and specified the guard fixture including both
positive controls. Its predicted acceptance criteria (`Doc.SymbolFacts.pas:1371`,
`CLI.pas:7727-7730`) both verified.

**Worth repeating the pattern:** an audit-for-more-instances review paired with an
implementation-plan review, both read-only, both citing file:line. The audit's
cleared list and the plan's "fix the check not the CFG" call were the two things
that would have cost the most to re-derive.

## Counts

| | before this stretch | now |
|---|---|---|
| drag-lint own source | 1581, 0 err | **1560, 0 err** |
| `overwrite-before-read` | 56 | **32** |
| YADF / YADFOT / YADFSetup | 6 / 6 / 10 | 6 / 6 / 10, **0 errors each** |
| INBOX notes | 108 | **59** |

**Zero `[error]`-severity findings in all four projects.** The only entries in
`drag-lint-fatal.log` are five deliberate injections from
`run_lsp_stdout_hygiene.ps1` proving the breadcrumb works -- not real failures.

## The bug family is NINE instances, six fixed

A dedicated audit of the whole `src\` tree (Fable) found **five more** beyond the
four fixed in the first stretch, and cleared fifteen candidates with reasons.
Full table in `INBOX-remaining-raw-text-scans-read-comments-as-code.md`.

Fixed this stretch, both user-visible-harmful:

* **`ParseDprUses`** (`Index.Closure`) -- anchored `\buses\b` on UNSCRUBBED text,
  and its ad-hoc stripper handled braces only. A `.dpr` header comment containing
  the word "uses" anchored the search; a commented-out member inside a real clause
  was harvested as a live unit. That is **phantom units in the compile closure**,
  i.e. in project index membership -- the input to everything else.
* **`ReadDeclLine`** (`Doc.Facts`) -- fixed at the choke point ALL directive
  detectors read through, so `procedure Foo; // override in subclasses` no longer
  documents Foo as an override and `// deprecated;` no longer fabricates a
  `<deprecated>` tag.

Both now scrub with `StripPasCommentsKeepLayout`, the ONE implementation that
already existed two units away. It blanks comments and **preserves string-literal
content** -- load-bearing, because `deprecated 'use Bar instead'` needs its
message.

Three left, in the index at priority 1: FormsMap launch/show detection (needs a
read-site change with a line-count risk, since FormsMap emits line numbers), TypeAt
hover inference, the `todos` verb (marginal, listed for completeness).

## `overwrite-before-read`: 56 -> 32, and its advice was the point

The rule flagged the nil-init before a `try` as a dead store, and **deleting that
store leaves an uninitialised variable on the exception path** -- following the
finding converted correct code into a crash. `ProtectedByFollowingTry`
(`FlowChecks`) suppresses it when the store is a member of the run of assignments
immediately preceding a `try` whose except/finally MENTIONS that variable.

Scoped to the CHECK, not the CFG, following the precedent `FreedInFinallyBlock`
set for object-leak's identical cause: the `try..except` handler edge models "the
exception fired after the body's assignments ran", and `used-before-assignment`
depends on the state that edge carries.

**The predicate is the sound one and the guard proves it.**
`run_overwrite_before_read_pretry.ps1` asserts that a store before a `try` whose
handler never names it STILL FIRES, alongside an ordinary dead store. Without
both, the fix would be indistinguishable from switching the rule off -- the trap
the group-E note warns about for this whole rule family.

**The 32 survivors are a different shape.** Sample before assuming.

## A regression I caused, and what it teaches

The dangling-else `exprIf` fix (first stretch) decomposed nests that had been ONE
OPAQUE ITEM -- and **opaque items are skipped by the read check entirely**. So
correcting the CFG made a latent defect reachable: one new false positive on
YADFSetup (`uYADFSetupMain.pas:140`),
`VerQueryValue(..., Pointer(Fixed), ...) and (Fixed <> nil)`.

Fixed by `CollectAndOrLeftDefs`, which carries the left-to-right short-circuit
refinement that `CollectInterfaceDerefs` **already had** for
`not-assigned-interface` -- the plain read check simply never had it, so the two
checks disagreed about the same idiom. Applied at the read check only, not inside
`CollectReadsAndCallDefs`, which feeds liveness and other rules.

It also retired a known limitation: `run_flow_store_precision.ps1` section B
asserted the short-circuit case still fires, with the note *"flip this when
intra-item evaluation order is modelled"*. Flipped.

**Expect more of this.** Anything the opaque-item path was hiding is now
reachable. That is a good trade, not a free one.

## NEXT -- in order

1. **Work `docs/INBOX-INDEX.md` priority 1**, top to bottom. Two of its six items
   are DESTRUCTIVE defects (`returns-type-baseline-destroys-malformed-blocks`,
   `shared-unit-empty-render-deletes-block`) and one of those is probably already
   closed -- **rebuild its 3-unit fixture and CHECK IT IN**; it has been
   re-diagnosed from scratch twice because the repro lived in a scratchpad.
2. **Re-measure before coding.** Two notes closed this pass on measurement alone.
   Several more are flagged for it in the index, notably
   `docdrift-4-survive-a-converged-autodoc` (comment-derived facts were a
   plausible cause and are now fixed).
3. **`group-E` sections beyond the first** -- `double-free` (42 findings, sampled
   6/6 false) is the next-largest known-wrong rule.
4. **The store-backed fix-path audit** (`audit-store-backed-fix-paths-for-stale-positions`)
   -- `doc-drift` and `missing-doc` write at store coordinates with no
   verification, and `tekReplaceInLine` clamps EndCol but not Col, so a stale
   column silently APPENDS rather than failing.

## Standing gotchas earned across both stretches

* **A closing brace inside a braced comment ends it early.** Cost FOUR builds now,
  every one of them in a comment explaining a comment-scanning fix. Name the
  delimiters in prose.
* **`lint <file>` is a silent subset of `lint-all`** -- whole-index rules are
  absent and it still prints `0 finding(s)`.
* **Anchor tests on the LAST match of a routine header** (interface +
  implementation both match).
* **Every guard needs a positive control**, and when a case cannot discriminate,
  say so in the output -- `run_lint_project_db_resolution.ps1` case 4 prints a
  `[NOTE]` for exactly that reason.
* **`tools\dumpnode` is already built** at `src\cli\Win64\Debug\dumpnode.exe`.
  Keywords are NAMED nodes (`kIf`, `kAt`, `kExcept`...), so "the first named
  child" is usually the keyword. Three bugs from this so far.
* Some `docs/INBOX-*.md` files ARE tracked (28 of them were), contrary to the
  "docs are untracked" convention -- so retiring a note can leave a tracked
  deletion. Stage both sides so git records a rename.
