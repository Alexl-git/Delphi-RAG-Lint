# RESUME -- 2026-08-13

> **SECOND HALF of this session appended at the bottom** (owner-directed):
> the DB-scheme generalisation, the YADF family driven from 149 to 10, the first
> ever measurement of YADFOT/YADFSetup, and DataCopy LoopZero rounds 1-2
> (493 -> 130). Read "PART TWO" below for current state.

# PART ONE -- Task 0 + the case dataflow fix + three rule-precision fixes

Continues `PLAN-2026-08-12-case-dataflow-fix-and-datacopy-cycle.md`. Tasks 0-3
and 4.1 are DONE. Tasks 4.2-4.4, 5 and most of 6 are NOT.

`main` = 2 new commits on top of `d21e7d3` (now **12 unpushed** -- this repo has
never been pushed; ask before pushing).

## What shipped

### Task 0 (BLOCKING) -- `lint-all --project` measured the WRONG index -- `d9afbd9`

`ResolveConsumerDbs` never read `AArgs.ProjectPath`. It took manifest sections in
declaration order, filtered by a platform detected from the **current working
directory**. From this repo, `--project C:\Projects\YADF\YADF.dproj` therefore
opened `ORM3-Micronite2027.sqlite` -- the first section. `--project` then
correctly scoped the FILE LIST to YADF's closure, and the intersection with a
foreign index is empty:

    before:  0 finding(s), 0 file(s) scanned, 7+ minutes (project-wide pass on a 2 GB index)
    after:   149 finding(s), 8 file(s) scanned, 18.6s -- identical to --db

Three parts: promote the project's own DB to the front via `ResolveProjectDb`
(the same function `resolve-dbs --project` and the IDE's Rebuild Index use);
derive the platform from the project's folder before falling back to cwd; and
select lint-all's "library" slot **by name** (`library-*`) instead of taking
whatever DB came second.

**That third part is worth its own line.** `CheckUsedUnitResolvable` parses the
platform back out of the library DB's file name (`library-Win64.sqlite` ->
`Win64`) to locate DCU-only units. Handing it another PROJECT's index made that
project's units count as "library" units AND silently disabled the DCU fallback,
because the name yields no platform. **DataCopy's `used-unit-not-resolvable`
went 99 -> 0.** That whole category was this one defect.

Guard: `tests\autotest\run_lint_project_db_resolution.ps1`. The pre-existing
scope test could not have caught it -- every one of its runs passes `--db`
explicitly, which is the one input that masks the bug. The new test never passes
`--db` and asserts the `--project` count EQUALS the `--db` count **with neither
being 0**; a test that passes at 0 == 0 is the test that would have missed this.

### Tasks 1-3 -- the `case` selector and else arm -- `511336e`

Both defects were in the `K = 'case'` block of `DRagLint.Analysis.Cfg.pas`, and
both came from assuming the parse tree's shape. The real shape, now printed by a
checked-in probe (`tools\dumpcase`, moved out of the gitignored `scratchpad\`):

    (case (kCase) <selector> (kOf) (caseCase ...)* (kElse) <stmt>* (kEnd))

* **The else body was never emitted.** The handler added a bare fall-through
  edge and stopped. Unlike `ifElse`, a case's else arm is neither a field nor a
  node -- it is a run of bare siblings after `kElse`, so `ChildByField('else')`
  was never going to find it.
* **The selector was never added.** The handler took "the first named child that
  is not a `caseCase`" -- but **keywords are named nodes in this grammar**, so
  that is the `case` keyword itself, and it then `Break`'d.

The open question the plan flagged ("what node type holds a case's else arm?")
is answered: **no node and no field.** The plan's Task 2 was explicitly
undiagnosed and warned against patching on a hypothesis; the mechanism turned out
to be the keyword-is-a-named-node fact, dumped rather than guessed.

Both tracked reproducers are silent: `YADF.Options.pas:593 EncodingOf` and
`YADF.Layout.pas:3325 CurLineLast`.

Five fixtures in `tests\autotest\run_case_dataflow.ps1`, **two of which assert
the findings STILL FIRE** -- the cheap fix for each defect would have passed the
positive cases while silencing a real rule. Case 4 is the sharp one: a local read
ONLY inside the else body separates "the else EDGE reaches the join" (which the
old code did have) from "the else BODY is in the graph" (which it did not).

### Two more rule-precision fixes, found by sampling YADF (not yet committed at time of writing -- see below)

* **`compiler-magic-comments` had no word boundaries.** `BUG` matched inside
  **DEBUG**, so `DEBUG_MODE`, "built with DEBUG symbols" and every
  `BUG_SOMETHING` test-case name was reported as an untracked work item. Fixed
  with `\b(TODO|FIXME|HACK|XXX|BUG)\b` -- `_` is a word character, which is what
  makes the boundary correct at both ends. Guard:
  `run_magic_comment_boundaries.ps1`. YADF 16 -> 13.
* **`concat-in-loop` matched any `X := X <binop> Y`.** No operator constraint and
  no operand constraint, so `i := i + 1` and `k := k + 2` were reported as
  quadratic string building -- and `i := i - 1` would have been too. Fixed with
  `operator: (kAdd)` plus "the right operand may not start with a digit or `$`"
  (`S := S + 1` does not compile, so that is type-safe reasoning without a type).
  Guard: `run_concat_in_loop_precision.ps1`, whose LAST assertion deliberately
  asserts the REMAINING limitation, so the day it is fixed the change is visible.

## Numbers (final, all three commits in)

| Project | before | after | why |
|---|---|---|---|
| YADF (`YADF.dproj`) | 149 | **141** | case fix -2, magic-comments -3, concat -3 |
| DataCopy (`DataCopy.dproj`) | 493 | **391** | `used-unit-not-resolvable` 99 -> 0 |
| drag-lint (`src\cli`) | ~1,869 (old, not comparable) | 1,971 | measured for the first time via `--project`; 214s |

All of it came from RULE fixes -- class 1 of the standard. **Not one line of
YADF's or DataCopy's source was changed, and not one `allow` was written.**
That is the intended shape: a rule fix is re-measured across every project at
once, and it is the only outcome that also improves the tool.

## Corrections to the plan's assumptions

* **DataCopy's doc-drift is NOT majority-false.** The plan predicted the 192
  would mostly evaporate. Sampled and grouped: 146 "managed facts block is out of
  date", 28 missing `<param>`, 14 missing `<returns>`. That is real autodoc work,
  not a rule defect -- `document --project --apply` is the answer, not a rule fix.
  The plan's other half was right, and bigger: `used-unit-not-resolvable` was
  **entirely** false and is now 0.
* **YADF is FIVE projects, not three**, plus ~130 files that must never be
  linted. Full map in `docs\INBOX-yadf-scan-coverage-map.md`. Headlines:
  `YADF.OptionsFrame.pas` is NOT an orphan (both `YADFOT.dproj` and
  `YADFSetup.dproj` compile it -- question closed); `Test\GuardTest.dproj` and
  `Test\OptionsTest.dproj` are owned, real, and in **no manifest section**;
  `Test\uMainForm.pas` is a genuine orphan; and `Test\Cases`, `Test\Snippets`,
  `Result\` and `Demo\` are formatter FIXTURE DATA -- `Result\YADF.dpr` is
  formatter OUTPUT of `YADF.dpr`, not a fifth program. A literal reading of
  "scan everything we own" would lint a corpus that contains a deliberately
  malformed unit.

## NEXT -- in this order

1. **Commit the two `.scm` rule fixes** if the battery that was running at
   write-time came back green (`rules\compiler-magic-comments.scm`,
   `rules\concat-in-loop.scm`, their two deployed copies under
   `third_party\dll-win64\rules` and `src\cli\Win64\Debug\rules`, and the two new
   tests). **The deployed copies are separate files** -- editing only `rules\`
   changes nothing at runtime.
2. **Task 4.2 -- LoopZero YADF.dproj properly.** It is at 144 with round 0 done
   and partial triage only. Remaining mix is dominated by complexity rules
   (duplicate-code 29, deep-nesting 16, boolean-expression-complexity 15) that
   the previous session already ruled on: do NOT bulk-mark them. The 13 surviving
   `compiler-magic-comments` are genuine marker words in prose ABOUT markers --
   YADF's job is emitting `// TODO -oYADF` into other people's code -- so they
   are `allow` candidates, class 3. Rebuild YADF first: `Test\run_tests.ps1`
   (22 scripts, 84 golden files) fails fast on a stale exe, and it is the
   strongest safety net in the whole plan.
3. **Tasks 4.3 / 4.4** -- YADFOT (design-time BPL, build with the IDE CLOSED) and
   YADFSetup. Both DBs date from 2026-08-12 07:41; reindex first.
4. **Add the two missing YADF test projects to the manifest** and decide
   `Test\uMainForm.pas` (delete or adopt). Until then, YADF cannot be called zero
   under the standard, because two owned files are not measured at all.
5. **Task 5 -- DataCopy.** Now 391. Commit its pre-existing dirty tree first
   (Mercurial, 5 modified + several untracked), labelled pre-existing. Note
   DataCopy is THREE projects, not two: `Tests\DataCopyTests.dproj` is also
   missing from the manifest. Its exes cannot run when built by msbuild
   (EurekaLog is IDE-injected), so "it compiles" is the verification ceiling.

## New backlog (all filed as INBOX notes)

* `INBOX-lint-rule-filter-leaks-other-rules.md` -- **two** defects in `--rule`.
  It does not filter strictly (`magic-literal` findings come back from a
  `--rule write-only-local` run), AND its validator only knows built-in ids, so
  `lint --rule compiler-magic-comments` **exits 2 with "unknown rule"** for every
  external `.scm` rule. That is the same `BuildCatalog` vs `BuiltinRegistry`
  blind spot the previous session fixed for `allow`, surviving at a second site
  (`DoLint`, `DRagLint.CLI.pas:6877`). It blocked triage twice today.
* `INBOX-concat-in-loop-is-type-blind.md` -- the remaining half of the concat
  fix, with the `string-equality-comparison` precedent to copy.
* `INBOX-yadf-scan-coverage-map.md` -- the coverage map above.
* Minor, unfiled: `lint-all --project` writes its report to the PROJECT ROOT
  (`C:\Projects\YADF\lint-report-20260813.txt`) while `--db` writes it into
  `_D-RAG\`. It litters the project of a repo that is not ours to dirty.

## Standing traps re-confirmed today

* The Write tool emits LF; `.pas`/`.dpr`/`.ps1` here are strict 7-bit ASCII +
  CRLF. Byte-check after every write -- it bit three files this session.
* `return @()` from a PowerShell function unrolls to `$null`. Use `return ,@()`.
  It made a correct silent lint run look like a broken one.
* Sampling paid off AGAIN: 2 of 6 `concat-in-loop` findings sampled on YADF were
  false, and that is what led to the rule fix. Sample ~12 before believing a
  count.

---

# PART TWO -- owner-directed continuation (2026-08-13, same session)

Four owner instructions drove this half:

1. *"YADF and related projects -- what do we still have to check?"*
2. *"All complexity rules in all projects: allow these as exceptions unless you
   can figure out those as false positives. Sometimes we do need large units."*
3. *"DataCopy -- make a branch off main and do 2-3 LoopZeros."*
4. *"By default and maybe always we need to use this scheme -- project DB +
   platform library unless somewhere is specified otherwise."*

## 4. The DB scheme is now the CENTRAL default

The owner's model is right and is now what the engine does. Answering the
"how did YADF open Micronite2027's DB?" question directly: **YADF always had its
own DB.** Nothing was mixed up in storage -- all three YADF projects have had
their own `_D-RAG` indexes throughout. The bug was purely in SELECTION.

`--project` is now applied ONCE, centrally, right after argument parsing rather
than per verb, because it kept being missed one verb at a time:

* `lint-all --project` was fixed in `d9afbd9`;
* `document --project` still opened `<cwd>\drag-lint.sqlite` and died with
  "index schema v19 < v21" from an unrelated project's DB -- which is what
  blocked DataCopy's autodoc.

Now: `--project` given AND no explicit `--db` -> `Args.DbPath` becomes that
project's own index. Every project-scoped verb (`document`, `refresh-findings`,
`forms-csv`, `uses-fix`, `check-unit`, ...) inherits it, including ones added
later.

**The three places "specified otherwise" can happen**, and there are only three:
an explicit `--db`; a manifest section's explicit `"db"`; a `"db"` in a
`.drag-lint.json`.

**Known caveat, filed:** project DB + library DB answers every *"what does this
code mean"* question, but NOT *"is this used anywhere we own"*.
`SaveOptionsToIni` is reported `unused-public-symbol` by `YADF.dproj` while
having 15 call sites in `YADF.OptionsFrame.pas`, which only YADFOT/YADFSetup
compile. See `INBOX-cross-project-symbol-use-defeats-single-project-rules.md`.

## 1 + 2. The YADF family

**It is five projects, and only one had ever been measured.**

| Project | before | after | note |
|---|---|---|---|
| `YADF.dproj` | 149 | **10** | 127 allows + 3 rule fixes |
| `YADFOT.dproj` | never measured | **119** | design-time BPL |
| `YADFSetup.dproj` | never measured | **90** | |
| `Test\GuardTest.dproj` | never measured | -- | **not in the manifest** |
| `Test\OptionsTest.dproj` | never measured | -- | **not in the manifest** |

209 findings were invisible before today. ~130 files under `Test\Cases`,
`Test\Snippets`, `Result\` and `Demo\` are formatter FIXTURE DATA and must never
be linted (`Result\YADF.dpr` is formatter OUTPUT, not a project).

`YADF.dproj`'s 149 -> 10:

* **87 complexity/metrics allows** -- sampled first; all ten complexity rules
  were accurate measurements marginally over generic thresholds on a formatter
  whose core unit is 5,619 lines. No false positives, so they are exactly the
  "allow and move on" case.
* **40 further allows** after per-category triage.
* **3 rule fixes** (below).

**The remaining 10 are ALL false positives or unmarkable**, which is why YADF is
not at zero and must not be forced there:

| rule | n | why it stands |
|---|---|---|
| `object-leak` | 3 | protected by the very next `try` -- see its INBOX note |
| `field-name-prefix` | 2 | flags 2 of `TGroup`'s 7 public fields, not `ForceClosed`; no policy |
| `unused-public-symbol` | 2 | one has 15 cross-project call sites |
| `length-zero-compare` | 1 | `W` is `TArray<string>`; `Length(W)=0` IS the idiom |
| `compiler-magic-comments` | 1 | anchored at line 1, a `{` -- unmarkable |
| `unit-too-large` | 1 | same line-1 anchor |

## 3. DataCopy -- branch + LoopZero rounds 1 and 2

Mercurial branch **`loopzero-2026-08-13`** off `default`. Pre-existing dirty tree
committed first, on its own, labelled as pre-existing (rev 90).

    493 -> 391   used-unit-not-resolvable 99 -> 0   (upstream rule fix, PART ONE)
    391 -> 165   round 1: autodoc, doc-drift 192 -> 21   (rev 91)
    165 -> 130   round 2: 35 complexity allows          (rev 92)

**Autodoc CONVERGED** -- a second `document --project` pass produced no change
(165 -> 165, doc-drift steady at 21), so it left the loop per the guard. The
remaining 21 need human text and cannot be generated.

## Engine changes in PART TWO

* **Central `--project` DB default** (above).
* **`inline-comment-in-multiline-args` now ignores `dl:ok` markers.** Writing 87
  markers manufactured 8 NEW findings of this rule, because markers land inside
  multi-line argument lists. Only a comment that is ENTIRELY a marker is skipped.
* **`allow` now verifies the marker ROUND-TRIPS.** It was silently writing
  markers that can never be read back -- appending `// dl:ok` to line 1 of a unit
  puts it inside the `{` header block comment, where `Parse` correctly refuses to
  see it. Exit 0, marker written, finding still firing: a false record of human
  review. Now refuses with the reason. (Those markers also hashed to `e3b0`, the
  SHA of empty content, so they could never self-invalidate either.)
* **`commented-out-code` OFF by default** -- owner ruling: *"I often do this and
  forget to clean it, or comment out debug output when I do not need it but might
  need later."* Note it had to be added in THREE places -- the catalogue flag
  alone does not reach `DefDisabled` for a BUILT-IN rule (`DoLint`, `DoLintAll`
  and `DoLintProject` each keep their own list; `missing-doc` hit the same trap).
* **`commented-out-code` added to `COMMENT_SENSITIVE`** -- measured: allowing it
  changed the comment, the rule stopped firing, and both markers were then
  reported unused. That is the loop-with-no-exit the list exists to break.

## The owner's reflow claim -- tested, and correct

*"YADF is not supposed to reflow anything into a line with a // comment."*
Verified by experiment. Control case: `Other(A,\n B, C)` with no comment WAS
joined onto one line; `Call(A, B, // note\n C, D)` was NOT. YADF suppresses the
join precisely because of the comment. So
`inline-comment-in-multiline-args` names a hazard its own named example does not
have. Filed for an owner ruling:
`INBOX-inline-comment-rule-premise-is-false-for-yadf.md`.

## NEXT

1. **`object-leak` -- the single biggest blocker to any true zero.** 25 findings
   across the four projects, **8 of 8 sampled false**, two causes (next-statement
   `try`; VCL Owner). Full write-up and a suggested fixture in
   `INBOX-object-leak-is-systematically-false.md`.
2. **LoopZero YADFOT + YADFSetup** -- 209 findings, untouched. YADFOT is a
   design-time BPL: build with the IDE CLOSED.
3. **LoopZero SortTest.dproj**, and add `GuardTest`, `OptionsTest` and
   `Tests\DataCopyTests.dproj` to the manifest -- three owned projects currently
   in no index at all.
4. **Decide `Test\uMainForm.pas`** -- compiled by no project. Delete or adopt.
5. The line-1 anchoring problem (`unit-too-large`, `compiler-magic-comments`)
   needs either a per-project config ruling or a smarter anchor.
