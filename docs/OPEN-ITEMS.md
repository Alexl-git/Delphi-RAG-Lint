# Open items -- the standing list

**This file is the answer to "what is left?".** It is meant to be re-read and
re-edited, not appended to. Last verified **2026-08-17** (session 25) against the
notes and, where stated, against a measurement taken that day.

Companion files:
* `docs\INBOX-INDEX.md` -- the narrative history of what was retired and why.
* `docs\INBOX-*.md` -- one file per open item. **7 open, 111 retired**
  (counted, not estimated: `Get-ChildItem docs\INBOX-*.md` minus `INBOX-INDEX.md`).
* `docs\RESUME-<date>-session<N>.md` -- the per-session state snapshot.

## How to read this

Every row says what is LEFT, not what the note is about, and carries a **plan?**
column that distinguishes three very different states: a fully specified plan, a
next step that is a MEASUREMENT rather than a fix, and blocked-on-the-owner.

**Nothing here should be started by re-reading its note and implementing what it
says.** Sessions 24 and 25 both found that roughly a third of note content was
stale: notes claimed defects that were already fixed, prescribed fixes that could
not have worked, and quoted numbers that had moved by an order of magnitude.
Re-measure first. Every row below marked *verified 2026-08-17* was.

---

## A. Impedes function

### A1. Intermittent `FOREIGN KEY constraint failed` aborts a section build
`INBOX-intermittent-fk-failure-on-incremental-reindex.md`

The only open item that stops the tool working. The run reports ERROR and exits
leaving the section **unbuilt**, while a scripted `index --all` sweep reports
success for every other section -- a silently missing index.

Seen ONCE, not reproduced; the database was verified NOT corrupt at the moment of
failure. Trigger shape: the first incremental reindex after many files changed at
once.

**Plan:** reproduction recipe only, no fix. **The next natural opportunity is the
DevExpress update** -- same shape, largest index. If it fires, KEEP THE LOG AND
THE DATABASE; a re-run succeeded last time, which is why it was never diagnosed.

### A2. Twelve databases answer from a two-versions-old extractor
Not an INBOX note -- an operational state, and the most likely source of a wrong
answer today.

`DB\SQL\drag-lint-sql`, `TableTools370P`, `MemTableFieldWizard`,
`dclDragLintWizard`, `CorpusScanDelphi`, `OCRPDF`, `TEST_PDFFragments`,
`drag_lint_graph`, `DragLintGraph`, `DragLintGraphDb`, `DragLintGraphDcl`,
`drag_lint_graph_tests` -- all on `v=1.2.2-alpha;schema=19`.

This is not theoretical: six ORM3 databases were in exactly this state on
2026-08-17 and had been returning results from an older parser until refreshed.
**~166 files total; it is a quick job.**

**Plan:** `index --all --only <Section>` for each. Note the v1.4.0-alpha bump
re-parses everything once anyway (see C3), so doing it alongside that costs
nothing extra.

---

## B. Real work, specified, unblocked

### B1. `AExtraStores` -- the cross-DB documentation ping-pong
`INBOX-buildfor-defaulted-args-diverge-between-entry-points.md`

`document --qname X --db A --db B` mines inbound facts from both stores and
writes them to source. The doc-drift checker rebuilds the block with
`{AExtraStores=}nil` (`Doc.Drift.pas:615`), cannot account for the entry, calls
the block stale, and `--fix` deletes it -- then `document` re-adds it. **Source
files churn back and forth.**

Fix as an **options record** read by the Fresh render, `Analyze`, both
`FixEdits*` and `BuildFor`. NOT "thread four args": of the four, `ABaseDir` is
dead unless `AIncludeSince`, `AComplexityMin` is latent, and `AIncludeSince` is
checker-side. Only `AExtraStores` is real. Bonus: clears 2 `too-many-parameters`.

**Status verified 2026-08-17.** A fixture exists at
`tests\autotest\pending_doc_drift_extra_stores.ps1`, deliberately named
`pending_*` so the battery does not run it. It is NOT yet proof: its first
version produced a false PASS because it never reindexed after
`document --apply`, and doc-drift's population comes from the INDEX
(`ListDocumentedSymbols`), not from the source on disk. The reindex step is now
in the script; **the ping-pong itself has still not been observed.**

**Plan:** finish the fixture until step 4 (single-store drift IS reported) goes
RED for the right reason and step 2 fails against the current build. Only then
write the options record. **Do not start with the refactor.**

### B2. Relax the scoped-resolve gate for pure type ADDITIONS
`INBOX-incremental-index-hangs-on-large-db.md`

Adding units to an index changes the declared type-name set, so
`ScopedResolveIsSound` declines and the calls resolve falls back to the whole
database -- documented at ~37 minutes on a 2 GB index. The announce half shipped
2026-08-17 (it was never a hang; it was a silent long pass).

**Measured prize, 2026-08-17, ORM3 with a 12-file delta:**

```
  scoped     46.7 s
  whole DB  195.5 s      call_edges digests IDENTICAL
```

4.2x, with byte-identical edges.

**Plan:** yes, and the verification harness already exists --
`tools\perf\scoped-resolve-ab.ps1`, with `DRAGLINT_NO_SCOPED_RESOLVE` as the A/B
hatch so it is one binary over one corpus. ~1 day, correctness-sensitive.

**Two ways that harness goes vacuous, both guarded:** a delta made by deleting
file rows makes files NEW and both sides decline scoping; a subject DB with a
stale fingerprint re-parses everything and blows the one-in-three limit. It now
shouts `*** VACUOUS ***` if run A did not take the scoped path.

**This is the item that would make the DevExpress reindex cheap rather than
merely observable.**

### B3. `lint-all` performance -- what is left
`INBOX-lint-all-project-wide-phase-dominates-runtime.md`

572 s -> 277 s over sessions 24-25, report byte-identical throughout. Remaining,
all verified 2026-08-17:

| item | cost | note |
|---|---|---|
| `.scm` rule queries | **54.35 s** | the largest single item in the run |
| `unused-unit-in-uses` | **16.55 s** | one `FindSymbolsByExactName` per distinct name |

**Plan: a measurement, not a fix.** Time individual RULES -- 114 queries -- before
touching anything. **Refuted, do not revive:** the quadratic
`Findings := Findings + X` measures **0.00 s**, and the `.scm` double parse is
real but worth **1.38 s of 271 s**.

---

## C. Blocked, deferred, or a decision

### C1. `exception-class-unit` -- needs FOUR OWNER RULINGS
`INBOX-exception-class-unit-and-generated-exception-types.md`

Scope is settled: **64 distinct messages on ORM3** (AST-based, session 22), not
the 400 that would have killed the feature. A session-25 re-measure produced "42"
and is **retracted in the note** -- wrong population, wrong set, regex instead of
AST.

**What blocks it is not the count.** Chiefly: in Stage 1, what does *"fits"*
mean -- a normalized message match, or a class-name match? Normalization is only
spec'd for Stage 3. Payoff 19 findings.

### C2. IDE / LSP -- needs one session at the keyboard
`INBOX-ide-lsp-ram-and-shim-todo.md`

Headless half DONE: `tools\lsp-diag\bpl-inventory.ps1` (209 + 63 + 182 registered
packages; the 4 absent files are all `__`-prefixed, i.e. disabled, which is
normal). Genuinely IDE-bound: TODO 2b error capture, live `ModuleMemorySize`
ranking, and disable-then-**re-measure**. A 32-bit-forwarding relay is testable
headlessly and is NOT started.

Checklist: `docs\PLAN-SESSION-25.md` section D.

### C3. The extraction fingerprint uses the PRODUCT version
`INBOX-extraction-fingerprint-uses-the-product-version.md`

Filed 2026-08-17. Every release bump re-parses every index whether or not
extraction changed -- 6,993 files for the library alone. Three options in the
note; **measure first** (do the last ten tags actually change extraction?).

---

## D. Housekeeping

* **ORM3 `lint-all` baseline SHA is stale by design.** Order changed (fixed), and
  the ORM3 refresh changed six databases' content, so the finding count itself may
  now differ. Record a new baseline on a quiet machine.
* **YADF** holds 8 owner-modified files plus an untracked `vendor\drag-lint\`
  (byte-identical mirror + README). Owner's call whether to commit.

---

## Traps that cost real time -- read before measuring anything

1. **Never invoke the engine by BARE NAME.**
   `NoDefaultCurrentDirectoryInExePath=1` is set on this machine, so
   `cd third_party\dll-win64` then `drag-lint lint-all ...` runs
   `third_party\dll\drag-lint.exe`, the frozen **Win32 build of 2026-07-05**, off
   PATH. It reported **33,626 findings against the real 14,764**, with ~20 `.scm`
   rules silently at zero. Use `.\drag-lint.exe`. The tell is the profile FORMAT.
2. **PowerShell holds native stderr until the process exits.** Redirect long runs
   through `cmd.exe`. This was mis-filed as an engine defect for two sessions.
3. **Do not run anything else during a timing run.** Two test suites alongside a
   measurement made its absolute numbers unusable.
4. **A timer with no CALL COUNT lies.** Three sessions were spent optimising a
   query that cost 2.41 s because the bucket named it and nothing counted calls.
5. **A DISTINCT-KEY count is what picks a memo's key.** The plan's `seealso` key
   would have hit zero times; the real repetition was 913,357 rows from 322
   distinct parents.
6. **Every guard needs a positive control AND a run against the unfixed build.**
   Three suites this session initially passed against the code they were meant to
   catch.
