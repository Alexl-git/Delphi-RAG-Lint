# Shared-Unit Documentation + Plugin Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a unit that several projects compile documentable without the projects fighting over its facts block, and clear the three engine defects that currently make any doc repair unverifiable.

**Architecture:** A unit declares itself shared with a `// dl:shared <projects>` marker (same family as the existing `dl:ok` review marker). `TDocDrift` stops byte-comparing the regenerated facts block and instead compares it structurally, forgiving *inbound* entries (`Called from:`, `Used by:`, `Used in units:`, `<seealso>`) that name units outside the current project's closure -- but only in a marked unit, and only when the entry is `certain`. The writer is unchanged: a narrower project still writes a narrower block, it is simply no longer told that block is stale. Three pre-existing defects on the repair path are fixed first, because without them no doc change can be measured.

**Tech Stack:** Delphi 13 Florence (RAD Studio 37.0), Win32 + Win64, tree-sitter grammar, SQLite symbol store, PowerShell 7 (`pwsh`) test battery, DUnitX not used here.

**Spec:** `docs/superpowers/specs/2026-08-13-shared-unit-doc-staleness.md`

## Global Constraints

- **Encoding:** every `.pas`, `.dpr`, `.ps1` and `.md` file is strict 7-bit ASCII with CRLF. The Write tool emits LF -- byte-check after every write. A `{` comment must never contain `}` or `{$` (it closes the comment early; this cost a build today).
- **Battery:** `pwsh -File tests\run_battery.ps1`, never `powershell.exe`. Baseline to beat: **265/265**.
- **Build:** `build\build_draglint_win64.bat` launched via PowerShell `Start-Process -Wait` with output redirected to a log; then read the log for `[dcc] Error`. Never `cmd.exe /c` from the Bash tool (hangs). Kill any running `drag-lint.exe` before the staging copy or it fails with "failed to stage".
- **Rule/deploy:** `rules\*.scm` is the tracked source; `third_party\dll-win64\rules` and `src\cli\Win64\Debug\rules` are gitignored copies with NO deploy step. A rule change does nothing until copied to both.
- **Manifest parity:** `third_party\dll-win32\drag-lint.json` and `third_party\dll-win64\drag-lint.json` must stay byte-identical (`run_manifest_parity.ps1` enforces it).
- **BPL builds:** build the design-time package with RAD Studio CLOSED.
- **Kill the episodic-memory `sync-cli.js` node parents at session start.** On 2026-08-13 they committed to `main` and edited YADF source mid-session.
- **Reproduce before implementing.** Three backlog items in a row have been implemented from a stated mechanism that turned out not to exist. Every task below that claims a cause has a step that proves it against a built engine first.

---

### Task 1: Diagnose and fix the stale-anchor skip that never clears

The autofix repair path currently cannot finish. On YADF, three consecutive
`lint-all --project --fix --apply` passes -- each followed by a full reindex --
printed the identical line:

```
autofix: applied 11 fix(es) across 0 file(s), 22 skipped (stale index) (.bak written)
```

Two defects in one line. **`applied 11` is false** -- `Touched` is 0, nothing was
written. And **`22 skipped` never decreases**, so YADF's last 2 `doc-drift`
findings are unrepairable by any command.

The count bug is certain from the source; the skip cause is NOT yet known, so
step 1 establishes it before anything is changed.

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas:6729-6733` (the apply/report block)
- Modify: `src/refactor/DRagLint.Refactor.TextEdit.pas` (`TTextEditApplier.Apply` -- the stale-position check)
- Test: `tests/autotest/run_autofix_apply_accounting.ps1` (create)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: a repair path that reaches zero on a converged project. Tasks 2 and 4 measure against it.

- [x] **Step 1: Reproduce and capture WHY each edit is refused**

Run, and keep the output -- this is the evidence the fix is judged against:

```powershell
$exe = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe'
cd C:\Projects\YADF
& $exe lint-all --project 'C:\Projects\YADF\YADF.dproj' --fix 2>&1 | Select-Object -Last 40
& $exe index --all --only YADF
& $exe lint-all --project 'C:\Projects\YADF\YADF.dproj' --fix --apply 2>&1 | Select-Object -Last 5
```

Then read `TTextEditApplier.Apply` and find the predicate that increments
`ApplySkipped`. Print, for each refused edit: the file, the line the edit
targets, the text the applier expected at that line, and the text actually
there. **Do not proceed until you can state, in one sentence, why the expected
and actual differ.** The two candidate causes, neither yet confirmed:
(a) edits are applied top-down so each earlier insert shifts every later edit's
line; (b) the anchor text recorded at build time does not match what
`TDocumenter.BuildFor` regenerated.

- [x] **Step 2: Write the failing test**

Create `tests/autotest/run_autofix_apply_accounting.ps1`. It builds a scratch
unit with THREE decls that all need the same fixable doc repair, indexes it,
and asserts the accounting is self-consistent and that a second pass converges.

```powershell
# after: & $Exe index $dir --db $db   and   & $Exe lint-all --db $db --fix --apply
# parse the summary line
$line -match 'autofix: applied (\d+) fix\(es\) across (\d+) file\(s\)(?:, (\d+) skipped)?'
$applied = [int]$Matches[1]; $touched = [int]$Matches[2]
$skipped = if ($Matches[3]) { [int]$Matches[3] } else { 0 }

Check 'applied is 0 when no file was touched' (-not (($touched -eq 0) -and ($applied -gt 0))) `
  'reporting work that was not done is worse than reporting none'
Check 'second pass converges: nothing left to skip' ($secondSkipped -eq 0) `
  'a skip that survives a reindex is unrepairable by any command'
```

- [x] **Step 3: Run it and watch it fail**

```powershell
pwsh -File tests\autotest\run_autofix_apply_accounting.ps1
```

Expected: FAIL on `applied is 0 when no file was touched` (the current line says
`applied 11 across 0 file(s)`), and/or on convergence.

- [x] **Step 4: Fix the accounting**

`FixCount` is the count of fixable FINDINGS, not of applied edits, and one
finding yields a delete+insert PAIR -- which is why 11 findings produced 22
edits. Report what actually happened:

```pascal
      var ApplySkipped: Integer;
      var Touched: Integer:= TTextEditApplier.Apply(Edits, not AArgs.NoBackup, ApplySkipped);
      { Report EDITS WRITTEN, not fixable findings. FixCount counts findings and
        one finding emits a delete+insert pair, so `applied FixCount` overstated
        the work whenever anything was refused -- and printed "applied 11 fix(es)
        across 0 file(s)", which is self-contradictory on its face. }
      var Written: Integer:= Length(Edits) - ApplySkipped;
      if ApplySkipped > 0 then
        SkipSuffix:= Format(', %d skipped (stale index)', [NFSkippedTotal + ApplySkipped]);
      Writeln(Format('autofix: applied %d edit(s) across %d file(s)%s%s',
        [Written, Touched, SkipSuffix, IfThen(AArgs.NoBackup, '', ' (.bak written)')]));
```

- [x] **Step 5: Fix the skip cause found in step 1**

Implement the fix your step-1 diagnosis names, and nothing else. If it is (a),
sort edits descending by (file, start offset) before applying so an earlier
write cannot move a later target. If it is (b), the anchor recorded by
`FixEditsForDocDrift` must be re-derived from the same render the applier
checks against.

- [x] **Step 6: Run the test and the battery**

```powershell
pwsh -File tests\autotest\run_autofix_apply_accounting.ps1
pwsh -File tests\run_battery.ps1
```

Expected: new test PASS; battery **266/266** (265 + this one).

- [x] **Step 7: Prove it on the real project**

```powershell
cd C:\Projects\YADF
& $exe lint-all --project 'C:\Projects\YADF\YADF.dproj' --fix --apply
& $exe index --all --only YADF
& $exe lint-all --project 'C:\Projects\YADF\YADF.dproj'
```

Expected: YADF `doc-drift` reaches **0** (it is stuck at 2 today), total 10 -> 8.

- [x] **Step 8: Commit**

```bash
git add src/cli/DRagLint.CLI.pas src/refactor/DRagLint.Refactor.TextEdit.pas tests/autotest/run_autofix_apply_accounting.ps1
git commit -m "fix(autofix): report edits written, and stop refusing every doc repair forever"
```

---

### Task 2: `document --project` must not report "nothing to document" on work the repair path can do

`document --project YADF.dproj` prints `53 public decl(s), nothing to document`
while `lint-all --project --fix` finds **23 real edits on the same store and the
same source**. Two writer entry points disagree, and the batch one is the one the
LoopZero cycle calls -- so "autodoc converged" has been reported on a project
that had not converged.

`ReportDocBatch` prints that line when `Length(ARes.Edits) = 0`
(`CLI.pas:8680`), so the batch PLANNER produced no edits. The per-symbol path
(`TDocLintRules.FixEditsForDocDrift` -> `TDocumenter.BuildFor`) produced 23.

**Files:**
- Modify: `src/doc/DRagLint.Doc.Document.pas` (the batch planner behind `TDocBatchResult`)
- Modify: `src/cli/DRagLint.CLI.pas:8680` if the summary wording needs to change
- Test: `tests/autotest/run_doc_batch_sees_drift.ps1` (create)

**Interfaces:**
- Consumes: Task 1's converging repair path (so "0 left" is reachable and provable).
- Produces: `document --project` whose edit count agrees with `lint-all --fix`'s fixable count for `doc-drift`.

- [x] **Step 1: Find the divergence**

Both paths reach `TDocumenter.BuildFor`. Find what the batch planner does that
the per-symbol path does not -- the candidate is a per-decl "does this need
documenting?" pre-filter that asks a different question than
`TDocDrift.Analyze` does. Name the exact predicate and line before writing code.

- [x] **Step 2: Write the failing test**

Create `tests/autotest/run_doc_batch_sees_drift.ps1`: index a scratch project
whose managed block has been hand-edited to be stale, then assert the two paths
agree.

```powershell
$batch = & $Exe document --project $dproj 2>&1        # dry-run
$fix   = & $Exe lint-all --project $dproj --fix 2>&1  # dry-run

$batchEdits = 0
if (($batch -join "`n") -match 'doc: \d+/\d+ decl\(s\), (\d+) edit\(s\)') { $batchEdits = [int]$Matches[1] }
$driftFixable = (($fix | Select-String 'doc-drift')).Count

Check 'the batch planner sees the drift the repair path sees' ($batchEdits -gt 0) `
  "document said 'nothing to document' while lint-all --fix found $driftFixable"
```

- [x] **Step 3: Run it and watch it fail**

```powershell
pwsh -File tests\autotest\run_doc_batch_sees_drift.ps1
```

Expected: FAIL -- `$batchEdits` is 0.

- [x] **Step 4: Make the planner ask the same question**

Route the batch planner's per-decl decision through the same
`TDocDrift.Analyze`-based test the repair path uses, so a decl with a fixable
drift signal is always planned. Add a comment naming this as the fourth incident
on the writer-vs-checker seam and pointing at the spec.

- [x] **Step 5: Run the test and the battery**

```powershell
pwsh -File tests\autotest\run_doc_batch_sees_drift.ps1
pwsh -File tests\run_battery.ps1
```

Expected: new test PASS; battery **267/267**.

- [x] **Step 6: Commit**

```bash
git add src/doc/DRagLint.Doc.Document.pas tests/autotest/run_doc_batch_sees_drift.ps1
git commit -m "fix(doc): batch planner reported 'nothing to document' on repairable drift"
```

---

### Task 3: The `dl:shared` marker -- grammar, reader, and verification

A unit declares that several projects compile it:

```pascal
unit YADF.Options;   // dl:shared YADF, YADFOT, YADFSetup
```

Derivation was considered and rejected: `resolve-dbs --in <file>` returns the
OWNING database only (measured -- it returns just `YADF.sqlite` for a unit that
YADFOT and YADFSetup also compile), so deriving the SET would mean opening every
index in the manifest on every run.

The project list is not load-bearing for the staleness algorithm -- "is this unit
shared" is the only input that is. The list exists so a human or an AI reading
the source learns the blast radius without running anything, and so the tool can
VERIFY the claim instead of trusting it.

**Files:**
- Modify: `src/lint/DRagLint.Lint.ReviewMarker.pas` (add `SHARED_MARK` + parse/insert, beside `REVIEW_MARK`)
- Create: `src/lint/DRagLint.Lint.SharedUnit.pas` (`TSharedUnit.IsShared`, `TSharedUnit.ProjectsOf`, `TSharedUnit.AddProject`)
- Test: `tests/autotest/run_shared_unit_marker.ps1` (create)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `TSharedUnit.IsShared(const AUnitPath: string): Boolean`
  - `TSharedUnit.ProjectsOf(const AUnitPath: string): TArray<string>`
  - `TSharedUnit.AddProject(const AUnitPath, AProject: string; out ANewText: string): Boolean` -- returns False when the project is already listed (idempotent no-op).
  Task 4 consumes `IsShared`; Task 5 consumes `AddProject`.

- [x] **Step 1: Write the failing test**

Create `tests/autotest/run_shared_unit_marker.ps1` with four fixtures: no marker;
marker with one project; marker with the project already listed; marker on a unit
whose line 1 is a `{` block comment.

```powershell
Check 'unmarked unit is not shared'        (-not (IsSharedPerCli $plain))
Check 'marked unit is shared'              (IsSharedPerCli $marked)
Check 'projects parse in written order'    (($projects -join ',') -eq 'YADF,YADFOT')
Check 'adding a listed project is a no-op' ($before -eq $after) `
  'idempotent: the menu item will be pressed twice'
Check 'marker is found below a line-1 block comment' (IsSharedPerCli $blockCommentFirst) `
  'line 1 here is often the { of a header comment -- the anchoring trap that already breaks unit-too-large'
```

- [x] **Step 2: Run it and watch it fail**

```powershell
pwsh -File tests\autotest\run_shared_unit_marker.ps1
```

Expected: FAIL -- no such CLI surface yet.

- [x] **Step 3: Implement the marker**

Add to `DRagLint.Lint.ReviewMarker.pas`:

```pascal
const
  SHARED_MARK = 'dl:shared';
```

Create `src/lint/DRagLint.Lint.SharedUnit.pas`:

```pascal
unit DRagLint.Lint.SharedUnit;

{ The `dl:shared` unit marker: a unit compiled by more than one project says so
  in its own source.

    unit YADF.Options;   // dl:shared YADF, YADFOT, YADFSetup

  WHY A MARKER AND NOT DERIVATION. `resolve-dbs --in <file>` answers with the
  OWNING database, one path -- measured 2026-08-13, it returns only YADF.sqlite
  for a unit that YADFOT.dproj and YADFSetup.dproj also compile. Deriving the SET
  would mean opening every index in the manifest on every run, to learn a fact
  that changes about once a year.

  WHY THE PROJECT LIST IS IN THE MARKER. It is not needed by the staleness rule,
  which only asks "is this unit shared". It is there so the blast radius is
  readable in the source without running the tool -- the case that motivated the
  whole feature -- and so `check-shared` can verify the claim instead of trusting
  it. A marker nobody checks decays into a lie, and this one decides staleness. }

interface

type
  TSharedUnit = class
  public
    /// <summary>True when the unit carries a `dl:shared` marker.</summary>
    /// <remarks>Scans the unit's HEADER REGION, not line 1 alone: line 1 of a
    /// unit here is frequently the `{` of a block comment, which is the same
    /// anchoring trap already recorded for unit-too-large and
    /// compiler-magic-comments.</remarks>
    class function IsShared(const AUnitPath: string): Boolean;
    /// <summary>The project names listed on the marker, in written order.</summary>
    class function ProjectsOf(const AUnitPath: string): TArray<string>;
    /// <summary>Adds AProject to the marker, creating the marker when absent.</summary>
    /// <returns>False when AProject is already listed -- an idempotent no-op, so
    /// the IDE menu item is safe to press twice.</returns>
    class function AddProject(const AUnitPath, AProject: string; out ANewText: string): Boolean;
  end;

implementation
```

Scan for the marker from the start of the file to the first line whose trimmed
text starts with `interface` (case-insensitive), inclusive. That covers the
`unit` line, a header block comment, and the `interface` line, and stops before
the body.

- [x] **Step 4: Add the CLI surface the test drives**

```
drag-lint shared-unit --in <file.pas> [--add-project <name>] [--apply] [--json]
```

Dry-run by default, matching `allow`. Print the resolved project list.

- [x] **Step 5: Run the test and the battery**

```powershell
pwsh -File tests\autotest\run_shared_unit_marker.ps1
pwsh -File tests\run_battery.ps1
```

Expected: new test PASS; battery **268/268**.

- [x] **Step 6: Commit**

```bash
git add src/lint/DRagLint.Lint.SharedUnit.pas src/lint/DRagLint.Lint.ReviewMarker.pas src/cli/DRagLint.CLI.pas tests/autotest/run_shared_unit_marker.ps1
git commit -m "feat(shared): dl:shared unit marker, reader and CLI surface"
```

---

### Task 4: Structured staleness -- forgive inbound facts a narrower project cannot see

`TDocDrift.Analyze` decides staleness with a whitespace-collapsed BYTE COMPARE of
the stored block against a freshly rendered one, so a block written while
project A's index was open is reported stale by project B, whose closure
truthfully holds fewer callers.

**RE-MEASURED 2026-08-13, engine `e6d0b8b` -- the premise HOLDS, and the doubt
recorded in `RESUME-2026-08-13c` is resolved.** That resume doc was right that
Task 4's ORIGINAL evidence had evaporated (YADF's residual `doc-drift` was the
seealso option mismatch, fixed in `9414826`, and the `dxRibbon` /
`TestCachedUpdates.dpr` junk was deleted from the source by the repair). It was
wrong that the underlying problem had gone with it. Read-only `lint-all
--project`, no `--fix`, on all three projects:

| Project | findings | `doc-drift` | was (47c5791) |
|---|---|---|---|
| YADF | 8 | **0** | 10 / 2 |
| YADFOT | 64 | **31** | 45 |
| YADFSetup | 58 | **34** | 45 |

The churn did not merely survive, it got WORSE: repairing YADF rewrote the shared
units' blocks under YADF's narrower closure, and YADFOT/YADFSetup went 45 -> 64
and 45 -> 58. Every drift finding lands on a shared unit -- `YADF.Options.pas`
21 under each, then `YADF.OptionsFrame.pas`, `YADF.Tokens.pas`, `YADF.Groups.pas`,
`YADF.Layout.pas` -- while YADF reports 0 on those same files. That is "project A
documents, project B calls it stale", measured, not inferred.

THE ONE CONCRETE DISAGREEMENT, as Step 2 of the resume doc demanded.
`YADF.Options.ParseEncoding`, stored on disk (`YADF.Options.pas:159`, written
under YADF):

```
/// Called from: YADF.Options.OptionTable (YADF.Options.pas), YadfMain.ParseFlags (YadfMain.pas)
```

the same decl rendered under `_D-RAG\YADFOT.sqlite`:

```
/// Called from: YADF.Options.OptionTable (YADF.Options.pas)
```

Every other line of the block -- `Calls:`, `Returns:`, `Complexity:`, `Pure` --
is byte-identical. YADFOT does not compile `YadfMain.pas`, so its closure
truthfully holds one caller fewer; the byte compare calls the block stale and the
repair would DROP `YadfMain.ParseFlags`, at which point YADF calls it stale in
the other direction. The loop has no fixed point. The forgiven entry here is
inbound, names a unit outside the current closure, and is `certain` -- all three
conditions of the rule below, on the first decl examined.

**Files:**
- Modify: `src/doc/DRagLint.Doc.Drift.pas` (the `ddFactsBlockStale` branch, currently `if CollapseAllWhitespace(CurBlock) <> CollapseAllWhitespace(Fresh)`)
- Modify: `src/lint/DRagLint.Lint.DocRules.pas` (`FixEditsForDocDrift` must not "repair" a block the checker now considers current)
- Test: `tests/autotest/run_shared_unit_staleness.ps1` (create)

**Interfaces:**
- Consumes: `TSharedUnit.IsShared` from Task 3; the converging repair path from Task 1.
- Produces: the behaviour LoopZero (Task 7) measures.

- [x] **Step 1: Write the failing test -- the assertion that would have caught all four incidents**

Create `tests/autotest/run_shared_unit_staleness.ps1`. Build ONE shared unit and
TWO projects that both compile it, index both, then:

```powershell
Check 'A documents, B sees no drift on the shared unit' ($driftUnderB -eq 0) `
  'the assertion that would have caught all four incidents on this seam'
Check 'B documents, A sees no drift on the shared unit' ($driftUnderA -eq 0)
Check 'a ? entry is still drift'            ($driftWithQuestionMark -gt 0) `
  'uncertainty-derived entries must still be cleaned'
Check 'an in-closure deletion is still drift' ($driftAfterRealDeletion -gt 0)
Check 'intrinsic drift is unaffected'         ($driftAfterParamTypeChange -gt 0)
Check 'an UNMARKED shared unit keeps old behaviour' ($driftUnmarked -gt 0) `
  'the marker is what opts in -- nothing changes for anyone who has not marked'
Check 'idempotent: document twice, no second edit' ($secondPassEdits -eq 0)
```

- [x] **Step 2: Run it and watch it fail**

```powershell
pwsh -File tests\autotest\run_shared_unit_staleness.ps1
```

Expected: FAIL on the first two checks -- each project reports the other's block stale.

> **BLOCKER FOUND 2026-08-13 while writing Step 1's fixture: Step 1's first two
> assertions cannot both hold under Step 3's rules, and closing the gap means
> changing the WRITER -- which this plan's Architecture line says is
> unchanged.**
>
> Step 1 asserts BOTH `A documents, B sees no drift` AND `B documents, A sees no
> drift`. Step 3 rule 4 says an entry present in FRESH but absent from STORED is
> ALWAYS drift, and the Architecture says "a narrower project still writes a
> narrower block, it is simply no longer told that block is stale."
>
> Walk it. B is the narrow project. B documents and writes a block with no
> `Called from:` entry for `AOnly` -- correctly, it cannot see AOnly. Now A
> regenerates: `AOnly` is in A's FRESH and not in STORED, which is rule 4, which
> is drift. So the second assertion fails BY CONSTRUCTION. Forgiveness is
> one-directional: it stops the NARROW project complaining about the wide
> project's block, and does nothing about the wide project re-adding what the
> narrow one dropped. The cycle still has no fixed point, it just runs one
> direction instead of two.
>
> This is not reachable by tuning the comparison. Rule 4 is the load-bearing
> half -- dropping it means a real new caller never gets recorded. The options
> are:
>
> 1. **The writer MERGES instead of replacing** -- when rewriting a marked
>    shared unit, keep the stored inbound entries whose units are outside this
>    closure and union them with the fresh ones. Both directions then converge
>    and the block becomes the true union across projects, which is what a reader
>    of a shared unit actually wants. Costs: the writer changes (contra the
>    Architecture line), and entries can only accumulate -- a caller deleted in
>    another project's code is never reaped by this project, so `check-shared`
>    becomes load-bearing rather than optional.
> 2. **One documenting owner per shared unit** -- the first project in the
>    `dl:shared` list writes the block; the others only read. Writer unchanged,
>    rule 4 unchanged, converges. Costs: a shared unit's docs are only as fresh
>    as the owner project's last run, and the menu item must not let a
>    non-owner write.
>
> **OWNER RULED 2026-08-13: OPTION 1, the writer merges.** This supersedes the
> Architecture line's "the writer is unchanged" -- that sentence is now wrong and
> the merge is the design.
>
> WHAT THAT MEANS FOR THE TASK. BOTH halves are needed and neither is sufficient
> alone:
>
> * **Checker** (Step 3) forgives a STORED entry missing from FRESH when the unit
>   is marked, the entry is out-of-closure, and the entry is `certain`. Without
>   this the narrow project reports the union block as stale forever.
> * **Writer** (new Step 3b) unions those same out-of-closure stored entries into
>   what it renders, so a write from ANY project preserves every other project's
>   entries instead of destroying them. Without this, rule 4 fires on the wide
>   project the first time the narrow one writes.
>
> The block on a marked unit therefore becomes the UNION across every project
> that compiles it, which is what a reader of a shared unit actually wants.
>
> CONSEQUENCE, stated plainly: entries can only accumulate. A caller deleted in
> ANOTHER project's code is never reaped by this project, because this project
> cannot see that it is gone -- it looks identical to an out-of-closure entry.
> Reaping is `check-shared`'s job, which makes that command load-bearing rather
> than optional. Do not paper over this in the doc comment.
>
> It also retires the `(+N more)` gap above as a CORRECTNESS hazard: a union
> needs no sound set-difference, so a truncated list is only a display cap. The
> conservative rule still applies to the CHECKER's forgiveness test, which is a
> set difference.
>
> ORDERING. The merged list must have a canonical order or the writer is not
> idempotent: under A the preserved entry appends after A's own, under B it
> appends after B's, and the two orders differ, so each project would rewrite the
> line the other just wrote. Sort the merged inbound entries. This changes byte
> order ONLY on marked units -- every unmarked unit renders exactly as it does
> today, so the "do not change that format" constraint above is respected.

- [ ] **Step 3: Implement the structured comparison**

Replace the byte compare with:

1. Split both blocks into fact lines; split inbound lines
   (`Called from:`, `Used by:`, `Used in units:`, and `<seealso>` crefs) into entries.
2. **Intrinsic facts** (`Calls:`, `Reads:`, `Writes:`, `Returns:`, `Complexity:`,
   `Mutates:`, `Pure`, `Touches:`) keep byte-compare semantics -- any difference is drift.
3. **Inbound facts:** an entry present in STORED but absent from FRESH is forgiven
   only when ALL hold:
   - `TSharedUnit.IsShared(<declaring unit>)`; AND
   - the entry names a unit that is not in the current project's closure; AND
   - the entry is `certain` -- rendered WITHOUT the trailing `' ?'`.
4. An entry present in FRESH but absent from STORED is always drift.

The rendering already carries what step 3 needs -- every entry names its unit in
parentheses, e.g. `YADF.Groups.ParseGroups (YADF.Groups.pas)`. **Do not change
that format**: re-rendering every block to a new shape would report mass drift
across all four projects for a cosmetic change.

**GAP FOUND 2026-08-13, before implementing: the plan above does not say what to
do about `(+N more)`.** Every inbound list is CAPPED and the overflow is rendered
as a `MoreSuffix` -- `Called from: A (a.pas), B (b.pas) (+18 more)`
(`Doc.Regions.pas:2164`, `:2167`, `:2186`). When either side of the comparison is
truncated, the visible entries are a WINDOW onto the list, not the list, so
"present in STORED but absent from FRESH" stops meaning what step 3 assumes: an
entry can vanish from the window purely because the cap fell differently, and a
genuine deletion can hide inside the `+N`. Set comparison over a truncated list
is not sound, and the caps differ between projects because the underlying counts
do.

RECOMMENDED RULE, conservative and statable: **forgiveness applies only when
NEITHER side of that fact line carries a `(+N more)` suffix. A truncated line
keeps today's byte-compare semantics exactly.** It cannot make anything worse
than the current behaviour, it needs no reasoning about what is inside the `+N`,
and the case that motivated the feature is not truncated -- the measured
disagreement on `YADF.Options.ParseEncoding` has two entries and no suffix. The
cost is that a heavily-called shared symbol keeps churning; that is a known,
bounded remainder to measure in Step 5, not a silent one.

Add an assertion for it: `Check 'a truncated inbound list is not forgiven'`.
Whatever is decided, decide it explicitly -- an unstated answer here writes wrong
facts into four real projects' source.

**THE `certain` TEST IS ONE-WAY, measured 2026-08-13.** `JoinRefs`
(`Doc.Regions.pas:2104`) emits the `' ?'` marker ONLY when the list is MIXED --
"a marker on EVERY entry distinguishes nothing". So in an all-uncertain list not
one entry carries `?`, and absence of the marker does NOT prove an entry is
certain. Reading it back off STORED TEXT can therefore only ever be sound in one
direction. Implement it that way and say so: **an entry carrying `' ?'` is never
forgiven; the absence of `' ?'` proves nothing and forgiveness rests on the other
two conditions.** Anything stronger is a claim the rendering cannot support.

**TRUNCATION IS REAL BUT A MINORITY, measured on the shared units:** 6 of 55
inbound lines carry `(+N more)` (`max_callers` is 5 in the manifest, not the
default). `YADF.Options.pas` -- 21 of the 31 drift findings -- has ZERO. So the
conservative rule costs little: a truncated line keeps today's byte compare in
the checker AND is rendered fresh, unmerged, by the writer. That leaves a small,
stated remainder of churn instead of an unsound set difference.

Comment the `certain` condition honestly: it is insurance, not the load bearer.
The junk it guards against (`TestCachedUpdates.dpr`, `dxRibbon`) was measured on
2026-08-13 to be absent from YADF's database entirely -- stale TEXT from the
union-DB era, which the per-project split already prevents from recurring. Keep
the test because it still discriminates `unverified` entries within a project.

- [ ] **Step 4: Keep the fix path in agreement**

`FixEditsForDocDrift` calls `TDocDrift.Analyze` and repairs anything `Fixable`.
Since the checker now forgives some differences, the fix path must forgive the
same ones or it will rewrite blocks the checker considers current -- incident
five. Verify by the idempotence check in step 1.

- [ ] **Step 5: Run the test and the battery**

```powershell
pwsh -File tests\autotest\run_shared_unit_staleness.ps1
pwsh -File tests\run_battery.ps1
```

Expected: new test PASS; battery **269/269**.

- [ ] **Step 6: Commit**

```bash
git add src/doc/DRagLint.Doc.Drift.pas src/lint/DRagLint.Lint.DocRules.pas tests/autotest/run_shared_unit_staleness.ps1
git commit -m "fix(doc): shared units keep inbound facts a narrower project cannot see"
```

---

### Task 5: IDE menu -- "Put a Shared Unit Marker"

**Files:**
- Modify: `src/delphi-plugin/DragLint.Plugin.Editor.pas` (menu construction ~line 5040; add `InvokeSharedUnitMarker`)
- Modify: `src/delphi-plugin/dclDragLintWizard.dproj` only if a new unit is added (it is not)

**Interfaces:**
- Consumes: `drag-lint shared-unit --in <file> --add-project <name> --apply` from Task 3.
- Produces: a menu item; nothing downstream depends on it.

- [ ] **Step 1: Add the invoke handler**

Place it in the `Generate && Export` submenu, beside `Auto-Document Whole Project...`:

```pascal
AddWrappedItem(SubGen, 'Put a Shared Unit Marker', InvokeSharedUnitMarker);
```

The handler resolves the active project name via the OTA
(`GetActiveProject`, base name without extension) and the current editor file,
saves the buffer if modified, then shells the CLI with `--add-project <proj>
--apply` and reloads. Report the outcome through `ShowMessage`: created, added,
or already listed.

- [ ] **Step 2: Build the BPL for BOTH platforms, IDE CLOSED**

```powershell
# rsvars + msbuild /p:Platform=Win32 then /p:Platform=Win64 on dclDragLintWizard.dproj
```

Expected: `WIN32_EXITCODE=0` and `WIN64_EXITCODE=0`.

- [ ] **Step 3: Verify in a live IDE**

Install the BPL, open `YADF.Options.pas` under `YADF.dproj`, invoke the item.
Expect `// dl:shared YADF` on the `unit` line. Invoke again: "already listed".
Switch to `YADFOT.dproj`, invoke: the marker becomes `// dl:shared YADF, YADFOT`.

**This step cannot be skipped or simulated.** The plugin is the one component
with no automated coverage, and the recorded traps (the `.dfm`-required
`EResNotFound`, the missing-`requires` W1033 collision, the non-virtual
`Destroyed`) all compile clean and fail only in a live IDE. See
`C:\Projects\Delphi_IDE_OptionsPage_HOWTO.md`.

- [ ] **Step 4: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.Editor.pas third_party/dll-win32/dclDragLintWizard.* third_party/dll-win64/dclDragLintWizard.*
git commit -m "feat(ide): Put a Shared Unit Marker menu item"
```

---

### Task 6: IDE menu -- About dialog, and move the debug items into it

The root menu currently ends with a `Diagnostics && Tests (alpha)` section of
nine items, plus `Show Resolved DBs (debug)...` in `Index && Maintenance`.

**Move into About/Diagnostics:** Run Diagnostics (didSave), Run AST Checks, Copy
Diagnostics (Current File), Import Build Log..., Open Plugin Log, Show Resolved
DBs (debug)...

**Keep on the menu** -- these are operations, not diagnostics: Lint Buffer
(Unsaved), Compile Buffer (unsaved), Compile && Diagnose, Full Compile Sweep,
and **Recover Buffer-Compile Files** (it restores source after a crash during a
buffer-compile -- the safety net for the one feature that temporarily overwrites
a `.pas`, so it must stay visible).

**Files:**
- Create: `src/delphi-plugin/DragLint.Plugin.AboutForm.pas`
- Modify: `src/delphi-plugin/DragLint.Plugin.Editor.pas:5119-5135`
- Modify: `src/delphi-plugin/dclDragLintWizard.dproj` (add the new unit to `contains`)

**Interfaces:**
- Consumes: nothing.
- Produces: `TDragLintAboutForm.ShowAbout` (a modal form).

- [ ] **Step 1: Build the About form, code-only**

Report, each with an explicit unavailable state rather than a blank:
engine exe path + `drag-lint --version`; plugin BPL version and bitness; index
schema version; the resolved DBs for the active project with row counts and
mtime; LSP connection status. Add a `Copy Diagnostics` button that puts the lot
on the clipboard, and leave room for future buttons.

**Create the `.dfm` even though the form is built in code.** A design-time form
without one raises `EResNotFound` at load in a live IDE -- recorded trap, it
compiles clean. Add the unit to the `.dpk`/`.dproj` `contains`.

- [ ] **Step 2: Rewire the menu**

Replace the `Diagnostics && Tests` block with a single
`AddWrappedItem(RootMenu, 'About drag-lint...', InvokeAbout);` and move the six
debug actions onto the About form. Delete `Show Resolved DBs (debug)...` from
`Index && Maintenance` (it is now on the About form).

- [ ] **Step 3: Build both platforms, IDE CLOSED, and verify live**

Install, open the menu: the debug section is gone, About opens and every field
is populated. Confirm `Recover Buffer-Compile Files` is still present.

- [ ] **Step 4: Commit**

```bash
git add src/delphi-plugin/DragLint.Plugin.AboutForm.pas src/delphi-plugin/DragLint.Plugin.AboutForm.dfm src/delphi-plugin/DragLint.Plugin.Editor.pas src/delphi-plugin/dclDragLintWizard.dproj third_party/dll-win32/dclDragLintWizard.* third_party/dll-win64/dclDragLintWizard.*
git commit -m "feat(ide): About dialog; menu is operations only"
```

---

### Task 7: LoopZero on YADF, YADFOT, YADFSetup, DataCopy

Only after Tasks 1-4 are green. Running it before the marker exists is what
churns the shared units against each other.

**Files:**
- Modify: `C:\Projects\YADF\YADF.Options.pas`, `YADF.Layout.pas`, `YADF.OptionsFrame.pas` (markers only)
- No drag-lint source changes expected. Any finding that turns out to be a rule
  defect goes back through fix-the-rule FIRST -- see the owner's standard.

- [ ] **Step 1: Mark the shared units**

Via the new menu item under each project in turn, or the CLI:

```powershell
foreach ($u in @('YADF.Options.pas','YADF.Layout.pas','YADF.OptionsFrame.pas')) {
  foreach ($p in @('YADF','YADFOT','YADFSetup')) {
    & $exe shared-unit --in "C:\Projects\YADF\$u" --add-project $p --apply
  }
}
```

- [ ] **Step 2: Verify the marker claims are true**

Warn on any listed project that does not compile the unit, and any unlisted one
that does. Fix the markers, not the checker.

- [ ] **Step 3: Run the cycle per project**

For each of `YADF.dproj`, `YADFOT.dproj`, `YADFSetup.dproj`, `DataCopy.dproj`:
reindex -> `document --project --apply` -> reindex -> `lint-all --project --fix --apply`
-> reindex -> `lint-all --project`. Repeat until two consecutive runs report the
same count.

- [ ] **Step 4: Record the numbers**

Baselines from 2026-08-13, engine `47c5791`:

| Project | now | after |
|---|---|---|
| YADF | 10 | |
| YADFOT | 45 | |
| YADFSetup | 45 | |
| DataCopy | 117 | |

- [ ] **Step 5: Sample before believing any count**

Read ~12 findings of the largest remaining rule, and **sample the ANALYSER, not
the source shape** -- reading shape without running the analyser has produced
three wrong conclusions on this codebase. Then triage: fix-the-rule,
fix-the-source, or `allow`, in that order. Never `allow` a false positive.

- [ ] **Step 6: Full battery, then commit**

```powershell
pwsh -File tests\run_battery.ps1
```

Expected: **269/269**.

---

## Known-open, deliberately NOT in this plan

- **Item D, the type-blind pair.** `concat-in-loop` is 15 findings on DataCopy
  alone -- the largest single rule left -- and `length-zero-compare` another ~1.
  Both need store-backed built-ins superseding the `.scm` queries, copying the
  `string-equality-comparison` precedent. Separate plan.
- **Should `dl:shared` also soften `unused-public-symbol`?** `SaveOptionsToIni`
  is reported unused by YADF while having 15 call sites in a unit only
  YADFOT/YADFSetup compile -- the same single-project blindness. **Owner
  decision pending**; recommendation is documentation-only for v1, so one
  mechanism changes one behaviour and the effect is measurable.
- **`used-before-assignment` intra-item ordering.**
  `docs/INBOX-used-before-assignment-real-shape-is-intra-item-ordering.md`.
- **DataCopy backup naming** -- owner ruled HOLD;
  `C:\Projects\DataCopy\NOTES-backup-naming-decision-2026-08-13.md`.
- **DataCopy tester B3** -- re-run needed with a real deny-ACL, since the
  folder read-only attribute is ignored by Windows (measured).
