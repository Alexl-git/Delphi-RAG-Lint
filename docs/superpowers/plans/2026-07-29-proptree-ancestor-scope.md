# Proptree Ancestor Scope Resolution — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.
>
> This plan is deliberately task-level rather than line-level: the engine code is large and the
> implementer should read the real code at the anchors given. If you want line-level steps, run
> `superpowers:writing-plans` over the spec first — the task boundaries below are already settled.

**Goal:** Stop `proptree` losing the inherited property surface when an ancestor's name is ambiguous, so `Name`, `Tag`, `Left`, `Top`, `Width`, `Height` become mappable for VCL and DevExpress targets.

**Architecture:** One shared scope rule (same unit → the inheriting unit's `uses` → framework prefix → decline) used by BOTH a new query-time fallback in the proptree climb and the existing index-time resolver. The query-time half is what makes existing indexes work without re-indexing.

**Tech Stack:** Delphi 13 (RAD Studio 37.0), Win64, `dcc64`; SQLite storage layer; PowerShell autotests.

Spec: `docs/superpowers/specs/2026-07-29-proptree-ancestor-scope-design.md`

## Where to work

**Branch `main`, at `674706a`, in a FRESH worktree.** Create it with
`git worktree add <scratch path> main` from any existing worktree of the repo.

Do NOT work in, or modify, either of these:
- `C:\Projects\Delphi-RAG-lint` — another team's checkout, on `feat/autodoc-phase3`, ~44 dirty files.
- `C:\Projects\Delphi-RAG-lint-converter` — on `feat/converter-editor`, carries a third workstream's uncommitted edits which have been destroyed twice already this session.

**Never run `git checkout`, `git restore`, `git stash`, `git clean`, or `git reset --hard`** anywhere. Never `git commit -- <pathspec>`.

## Global Constraints

- `.pas` files: strict 7-bit ASCII, CRLF, no BOM. Verify working-tree bytes before committing.
- DocInsight `///` on public surface; the doc-comment and the test must agree.
- **No schema change.** `type_ancestors` and `unit_uses` keep their shape.
- **Never resolve a `Vcl.*` class's ancestor to an `FMX.*` class, or the reverse.** This is the whole point.
- Keep the existing "when unsure, don't claim" policy: declining is correct, guessing is not.
- `--no-write-back` must stay honoured by any new resolution path.
- Do NOT use `library-Win32.sqlite` for anything — it is a broken 9.1 MB fragment. Use `C:\Projects\.drag-lint\library-Win64.sqlite`.
- Build with `build/build_draglint_win64.bat` via PowerShell `Start-Process -Wait` with output redirected to a log, then read the log. Do **NOT** run `cmd.exe /c "somebuild.bat"` from the Bash tool — it hangs until timeout.

## Code anchors (verified 2026-07-29 on `674706a`)

| What | Where |
|---|---|
| Proptree ancestor climb, skips unresolved rows | `src/report/DRagLint.Convert.PropTree.pas:278-304` (`ClassChain`) |
| Existing per-hop climb with per-class FileId scope — the model to follow | `src/report/DRagLint.Convert.PropTree.pas:477-537` (`ResolveViaBridgedAncestry`, `Climb`) |
| Forward-decl detection (already correct) | `src/report/DRagLint.Convert.PropTree.pas:231-234` (`IsForwardDeclClass`) |
| Index-time ancestor resolution, writes `type_ancestors` | `src/storage/DRagLint.Storage.SQLite.pas:3477-3641` (`ResolveAncestry`) |
| The id-based scope test that fails | `src/storage/DRagLint.Storage.SQLite.pas:3490` (`CandInScope`) |
| Declines and writes `'?'` | `src/storage/DRagLint.Storage.SQLite.pas:3595-3624` |
| Textual scope match that does NOT need `target_file_id` | `src/storage/DRagLint.Storage.SQLite.pas:2458-2551` (`ResolveTypeNameToClass`, `PickCandidate`, `LoadScopeNames`, `IsStub`) |
| Transitive reader used by proptree | `src/storage/DRagLint.Storage.SQLite.pas:3861` (`GetTransitiveAncestors`) |
| Uses-clause storage | `unit_uses(file_id, unit_name, target_file_id)`; `GetUnitUsesForFile`, `FindUsersOfUnit` |
| Populates `target_file_id` — currently leaves NULLs | `ResolveUnitUseTargets` |
| Autotest fixture template (synthetic VclKit/FmxKit/CxKit hierarchy with a decoy) | `tests/autotest/run_proptree_ancestry_bridge.ps1` |

## Tasks

### Task 1 — Baseline, then a failing hermetic test

- [ ] Capture the CURRENT behaviour so regressions are detectable. For each of
  `Abcbtn.TabcToggleBtn`, `Vcl.Controls.TControl`, `Vcl.Controls.TWinControl`,
  `Vcl.Controls.TGraphicControl`, `Vcl.StdCtrls.TEdit`, `cxButtons.TcxButton`: run
  `proptree --qname <X> --no-write-back --format json --db <library-Win64>` and record the leaf
  count and whether `Name`/`Left` are present. Save to the workspace as `baseline.md`.
- [ ] Extend `tests/autotest/run_proptree_ancestry_bridge.ps1`'s synthetic hierarchy with a class
  whose ancestor name is ambiguous between a `Vcl`-like and an `FMX`-like unit, and assert the
  `Vcl` one wins and the `FMX` one is never chosen (criteria 1-5).
- [ ] Run it and watch it FAIL for the right reason. Commit the test.

### Task 2 — The shared scope rule

- [ ] Implement one function that, given the inheriting class (its FileId/unit) and the candidate
  ancestors, applies: same unit → unit named in the inheriting unit's `uses` (textual, either
  section) → same framework prefix (`Vcl.` / `FMX.` / `Winapi.`) → decline.
- [ ] Wire it into `ResolveTypeNameToClass`'s `PickCandidate` so the query-time path uses it.
  Keep stub-dropping (`IsStub`) behaviour intact.
- [ ] The hermetic test from Task 1 should now pass. Commit.

### Task 3 — Query-time fallback in the climb (the part that works without re-indexing)

- [ ] In `ClassChain`, when `GetTransitiveAncestors` yields an unresolved row, fall back to a
  per-hop climb modelled on `ResolveViaBridgedAncestry.Climb`, resolving each hop with
  `ResolveTypeNameToClass(name, <FileId of the class doing the inheriting>)` — criterion 7. Do not
  use the root class's FileId.
- [ ] Guard against cycles and cap the climb depth.
- [ ] Honour `--no-write-back`.
- [ ] Verify against the REAL `library-Win64.sqlite`, read-only: `Vcl.StdCtrls.TEdit` and
  `cxButtons.TcxButton` now return `Name`, `Tag`, `Left`, `Top`, `Width`, `Height`, `Visible`,
  `Hint` (criteria 8-9) **with no re-index**. Commit.

### Task 4 — Index-time repair

- [ ] Fix `ResolveUnitUseTargets` so `unit_uses.target_file_id` is populated when a `uses` name
  matches an indexed file (criterion 12). Confirm on a small freshly-indexed fixture, NOT by
  rebuilding the library index.
- [ ] Make `CandInScope` fall back to the textual match when `target_file_id` is NULL, so a
  re-index is not required for correctness. Commit.

### Task 5 — Regression verification

- [ ] Re-run the Task 1 baseline commands and diff against `baseline.md`: `Abcbtn.TabcToggleBtn`
  must be unchanged (3905 leaves), and `TControl`/`TWinControl`/`TGraphicControl` must still reach
  `System.Classes.TComponent` (criteria 10-11).
- [ ] Run all proptree autotests plus `run_convert_rules.ps1` — `run_proptree.ps1` was 20/0 and
  `run_convert_rules.ps1` 26/0 (criterion 13).
- [ ] Measure `proptree cxButtons.TcxButton` wall-clock before/after; if the per-hop fallback made
  it materially slower, memoize per query.
- [ ] Commit, and write a short reply note to
  `docs/INBOX-REPLY-proptree-ancestor-scope-<date>.md` in BOTH checkouts saying what was fixed and
  that existing indexes are repaired without re-indexing.

## Then: the converter side

Once `proptree` returns the full surface, rebuild and re-stage the editor
(`build/_build_convrules_editor_local.bat` on `feat/converter-editor`) and confirm in the GUI that
`Name`, `Tag`, `Left`, `Top` now appear in the To pool for `cxButtons.TcxButton` and can be
assigned. The Examine feature will then mark them green from a real `.dfm` with no further change.
