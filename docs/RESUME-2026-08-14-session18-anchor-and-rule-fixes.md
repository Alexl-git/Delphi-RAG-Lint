# RESUME -- 2026-08-14 (session 18)

Supersedes `RESUME-2026-08-13f-autodoc-closed-and-loopzero.md`.

## Status

Branch **`session18-q0-orphan-anchor`**, 8 commits ahead of `main`, **not pushed**.
`main` untouched at `17e3fb1` (+25 older unpushed). Battery **271/271**.
YADF (git) @ `3f2bf95` · DataCopy (hg) @ `772a0a96806c` -- both committed.

Tracked `src/ tests/ rules/` are CLEAN. `docs/INBOX-*.md` are intentionally
UNTRACKED (project convention) -- ~78 of them; do not `git add docs`.

| commit | what |
|---|---|
| `21ef119` | stale-anchor ROOT CAUSE + Q0 truncation exemption + `doc-orphan-block` |
| `cb44bab` | `concat-in-loop`: array append is not string concat |
| `db28d8a` | autodoc regeneration of our own source (820 edits) |
| `a097153` | `unsafe-shellexecute`: fixed-scheme URI exemption |
| `2e25e78` | doc regen for the above |
| `b3be650` | shared-unit: never delete another project's contribution |
| `eec91d2` | SharedFacts header: close the empty-render hole |
| `f5c99cf` | doc-drift: thread the manifest caps into the CHECKER |

## Counts

| project | start of session | now |
|---|---|---|
| drag-lint | 1883 (1 error) | **1607, 0 errors** |
| YADF | 6 | 6 |
| YADFOT | 14 | **8** |
| YADFSetup | 15 | **10** |
| DataCopy | 49 | **48**, 0 errors |
| orphan blocks (all repos) | 2 | **0** |

## THE BIG ONE: the stale-anchor bug was ONE TRAILING NEWLINE

`TTextEditApplier` splits an insert's Text on CRLF/LF and inserts each part as a
line (`Refactor.TextEdit:423`), so a Text ending in a break split to a trailing
EMPTY part and **every replace wrote one blank line more than it deleted**.
Gap 1 -> 2 exceeds `AllowGap = 1`, so `FindDocRegionAbove` could never associate
that block again and every later run took the bare-insert path. Self-inflicted,
no second project needed. `a233d1d` and `CommentRunStartAbove` were both patches
on the symptom.

Validated at scale: **820 edits across 29 files -> 0 orphan blocks.**

## The lesson worth carrying: CONVERGENCE IS NOT CORRECTNESS

At `b65b2f9` all three YADF projects reported "nothing to document" **while
`YADF.Options.pas` carried a stacked orphan pair**. doc-drift walks SYMBOLS; an
orphan belongs to none, so it -- and every gate built on it -- was blind BY
CONSTRUCTION. Hence the new FILE-level rule `doc-orphan-block`. A fixed-point
check is only as wide as the population it iterates, and damage that removes an
item from that population is self-concealing.

## NEXT -- the plan, in order

1. **OWED: regression guard for checker/writer cap parity.**
   `docs\INBOX-OWED-guard-for-checker-writer-cap-parity.md`. The `f5c99cf` fix is
   verified on the real defect but has NO guard. TWO fixture attempts went
   VACUOUS -- read that note before trying a third; it records both dead ends.
   Cheaper alternative suggested there: assert on the REAL corpus that a
   converged autodoc leaves zero `managed facts block is out of date`
   (EnumHelper.Generate lives in it, so re-breaking fails immediately).

2. **`used-before-assignment`** --
   `docs\INBOX-used-before-assignment-out-arg-in-large-routine.md`. The recorded
   cause is REFUTED by a 10-case probe matrix now in that note: neither the else
   branch NOR the open-array read fires it alone, only their CONJUNCTION plus an
   enclosing `if`. CFG (`Cfg.pas:620`) and lattice (`Lattices.pas:1281`) were
   both inspected and are CORRECT. Next step is a BISECT, not a fix -- strip E1
   down one feature at a time and watch which removal silences it. Look at
   `FlowChecks.pas:674-698`, which collects Reads and CallDefs and runs the read
   check BEFORE applying the item's own CallDefs. 7 findings on DataCopy, 2 on
   YADFOT; do NOT `allow` them (the flagged line is a WRITE).

3. **`review-marker` matches EXAMPLE markers in prose** --
   `docs\INBOX-review-marker-matches-example-markers-in-prose.md`. Blocks a true
   LoopZero zero. `Parse` takes ONE LINE so it cannot see block-comment state;
   the fix belongs in the file walker and needs `TSharedUnit.ScanHeader`'s
   comment-state machine. HIGH RISK: this is the SUPPRESSION mechanism -- wrong
   in the other direction and every `dl:ok` silently stops working across all
   projects. Do it against the three `run_review_marker_*.ps1` suites.

4. **`Calls:` harvests ENGLISH WORDS from prose -- 150 corpus-wide** --
   `docs\INBOX-calls-list-harvests-english-words-from-prose.md`. Arguably the
   biggest defect found this session and NOT yet touched. `constantly`,
   `unreferenced`, `untouched`, `until`, `yet`. One (`defect`, in
   Doc.SharedFacts) was written by THIS session's own autodoc pass from a comment
   just written beside it. Documentation asserting calls that do not exist, and
   self-reinforcing since rendered facts become prose the next extraction reads.
   Third unit to hit the "a text scan cannot tell code from comment" trap.
   150 is a FLOOR (capitalised prose words are not counted by that test).

## Gotchas paid for THIS session

* **NEVER reindex a PROJECT db with a folder scan** (`index <dir> --db <p>`) --
  it destroys per-project scoping. YADFOT and YADFSetup came back byte-identical
  (125 files / 2795 symbols each). Use `index --all --only <Section> [--rebuild]`.
* **Edit a source file and doc-drift inflates until you REINDEX.** Cost me a
  wrong reading (1605 -> "1618") mid-session.
* **Rebuild before the battery** if autodoc touched sources, or
  `run_exe_freshness` fails -- which it did, correctly.
* The repo's tripwires caught me three times: encoding guard (Write tool emits
  LF), `run_docrules_catalog`'s hardcoded rule count, and exe freshness. They
  work; bump the counts deliberately.
* **`document --project` takes a `.dproj` PATH**, not a project name.
* A literal `del ` inside a PowerShell string can trip a safety hook.
* `lint <file>` over ~100 files exceeds the 10-min tool cap -- read
  `doc-orphan-block` out of ONE `lint-all` instead.
* **A guard test that passes can still be testing NOTHING.** Both cap-parity
  fixtures passed their real assertions while the precondition proved they were
  vacuous. Always assert the precondition that the fixture is in the state the
  test claims.
