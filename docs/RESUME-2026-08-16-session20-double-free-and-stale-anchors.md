# RESUME -- 2026-08-16 (session 20)

Supersedes `RESUME-2026-08-15-session19b-inbox-triage-and-flow-fixes.md` for
current state; that one still holds the INBOX-triage detail.

## Status

Branch **`session18-q0-orphan-anchor`**, **not pushed**. `main` at `17e3fb1`.
Backlog is still `docs/INBOX-INDEX.md`.

| | before | now |
|---|---|---|
| drag-lint own source | 1575, 0 err | **1535, 0 err** |
| `double-free` | 42 | **0** |
| `overwrite-before-read` | 32 | 34 (+2, both GENUINE) |
| priority-1 INBOX items | 6 | **3** |

## What shipped

### 1. `double-free` 42 -> 0 (commit `730fa36`)

Re-measured (42, unchanged), then read **all 42** against source -- not a
sample. Every one false, and they were **three separate bugs**, which is why the
note's single "loop-invariance" fix would not have closed it:

* **A -- the freed expression was not the variable (~15).**
  `DetectFreedVarKind` resolved the operand with `LeftmostBaseVar`, which walks
  DOWN to the leftmost identifier, so `ColKv.Value.Free` and `FieldMaps[I].Free`
  were credited to the base var. `FreedOperandVar` now requires the operand to
  BE the variable. **Deliberately not applied to `DetectFreedVar`** (object-leak's
  escape lattice): there the loose reading only ever SUPPRESSES a finding, so it
  is the conservative one. Same code, opposite correct answer, depending on which
  direction an error points.
* **B -- the for-in iterator is rebound every pass (~15).** The CFG already
  recorded it in `TCfgBlock.EntryDefs` and `TDefiniteAssignment` already honoured
  it; `TFreedState` did not. `ApplyEntryDefs` is now the one implementation both
  lattices and both `FlowChecks` replays call, differing only in the value
  written (True = assigned, False = not-dangling).
* **C -- an inline `var X := Expr` was not a definition at all (~11).**
  `AssignmentTargetIndex` resolved a `varAssignDef` lhs with `NamedChild(0)`,
  and **the `var` KEYWORD is a named child**, so it looked up a routine var
  called "var" and returned -1. **Fourth bug in this tree from "keywords are
  NAMED nodes."** Fix: `FirstIdentChild`, which `LeftmostBaseVar` was already
  using two functions away.

Guard `tests\autotest\run_double_free_loops_and_members.ps1`, **7/7**, three
positive controls. The load-bearing one is **GenuineInLoop**: ONE object created
outside a loop and freed inside it is a real double free from the second
iteration on, and still fires -- that is what separates "the object is
per-iteration" from "the free is in a loop".

**Fix C had a blast radius and it was worth measuring.** It exposed a latent
object-leak FP (`var Re := TRegEx.Create`) because `TypeIsRefCountedOrValue`
decides from the DECLARED type and an inline var has none -- the guard that
already existed, and already named TRegEx in as many words, had nothing to read.
Closed in the same pass by `ConstructedTypeText`. It also added **2 genuine**
`overwrite-before-read` findings (`FormsMap.pas:1008`, `MCP.Server.pas:1082`)
that the rule could not see before.

### 2. The unanchored pure deletion -- a NON-defect, and how I nearly shipped a lie

`TDocumenter.BuildFor` emits four edits. `StampAnchor` was called at **three**;
the fourth -- *"the ONE place the engine emits a pure deletion"* -- was not.
Found by counting: `find-callers StampAnchor` -> 3, `tekDeleteLines|
tekInsertLines` -> 4.

**I wrote the guard, and it passed WITHOUT the fix.** So I measured instead of
assuming. With the stamp removed and the index deliberately stale, all three
entry points already refuse and never reach the branch:

| entry point | stale result |
|---|---|
| `document --unit` | `nothing to document` |
| `document --qname` | `up to date (no change)` |
| `lint-all --fix --apply` | `no fixable findings` |

`Existing` is recomputed from the **current file text**, so a store line that no
longer holds the declaration yields no engine-owned region and no edit. The
store coordinate is an anchor to search near, not a span to delete blindly --
the exact property the note assumed was missing.

The stamp stays, for consistency and against a future store-coordinate caller.
**The guard was deleted rather than shipped**: an assertion that is green with
and without the change advertises coverage that does not exist, which is worse
than no test. The measurement lives in the code comment at the site.

**The lesson is the reusable part.** "Count the emit sites, count the guard
sites, the difference is the bug" is a good *hypothesis generator* and a bad
*conclusion*. Two counts disagreeing shows an inconsistency, not an exposure --
reachability is a separate question and has to be measured. Had the guard not
been written first, this would have shipped as a fixed defect with a green test
proving nothing.

## THREE priority-1 notes closed by RE-MEASURING, not coding

This is now the dominant way progress happens here, and it keeps being cheaper
than the alternative:

* `shared-unit-empty-render-deletes-block` -- asked to "rebuild the 3-unit
  fixture and CHECK IT IN this time". **It was already checked in**, inside
  `run_shared_unit_staleness.ps1:337-352`, with three assertions naming this
  defect's mechanism verbatim. Reading the guard file first would have cost a
  minute.
* `audit-store-backed-fix-paths-for-stale-positions` -- **~80% stale.** Its
  three headline claims (`tekReplaceInLine` silently appends; there is no shared
  boundary assertion; the doc paths verify nothing) are all now false:
  `ReplaceEditIsValid` rejects a past-EOL Col, `AnchorIsValid` +
  `ExpectLine`/`ExpectText` IS the one shared assertion, and `StampAnchor` arms
  it. Only the fourth-edit-site gap above survived.
* (Session 19b had already closed `naming-autofix-corrupts-source` the same way.)

**The mechanism is always the same:** a note records the world as it was when
WRITTEN, and nothing walks back to amend it when the fix lands. So: **read the
guard file and re-run the measurement before writing any code.**

## NEXT -- in order

1. **Priority 1 has three items left:**
   `remaining-raw-text-scans-read-comments-as-code` (3 of 9 instances left:
   FormsMap launch/show, TypeAt hover, the `todos` verb),
   `bare-except-anchor-defeats-a-hand-written-marker` (take the `@hash` churn
   once, deliberately), `returns-type-baseline-destroys-malformed-blocks`
   (DESTRUCTIVE, unverified -- **re-measure it first**, on this session's
   evidence it is as likely to be stale as not).
2. **Expect more from fix C.** Inline `var X := ..` now registers as a
   whole-var definition for every rule reading `AssignmentTargetIndex`. Only +2
   surfaced on this repo, but no other project has been measured since.
3. `double-free` is 0 here; **it has not been re-measured on YADF/DataCopy.**

## Standing gotchas (carried forward, all still true)

* **Keywords are NAMED nodes** (`kVar`, `kAt`, `kIf`, `kExcept`) -- four bugs
  now. `tools\dumpnode` is already built at `src\cli\Win64\Debug\dumpnode.exe`.
* **Every guard needs a positive control**; the cheap fix for any dataflow rule
  is to stop reporting.
* **A closing brace inside a braced comment ends it early.** Name delimiters in
  prose.
* **`lint <file>` is a silent subset of `lint-all`.**
* **Anchor tests on the LAST match of a routine header.**
* **Rebuild before the battery** or `run_exe_freshness` fails (correctly -- it
  did, mid-run, because a source edit landed while the battery was going).
* **Never reindex a PROJECT db with a folder scan** -- `index --all --only <Section>`.
* **Edit a source file and doc-drift inflates until you REINDEX.** Regenerate
  managed blocks with `document --unit <file> --apply` (scoped, not `--project`).
* Battery ~20 min, auto-enumerates `run_*.ps1`; never rebuild while it runs.
* The Write tool emits LF; `.pas`/`.dpr`/`.ps1` are strict 7-bit ASCII + CRLF --
  **normalise every new `.ps1` before checking it in.**
