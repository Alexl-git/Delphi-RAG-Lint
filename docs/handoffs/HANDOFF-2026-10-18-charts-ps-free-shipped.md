# HANDOFF 2026-10-18 -- charts -- PS-free shipped (merged, deployed); account move

## Status
- PS-free charts is MERGED and PUSHED by the engine session (`delphi-rag-lint-a7`):
  `charts/ps-free` @ `eb4314ad` -> main `e2231cb3`; origin/main = `7f437dca`.
- `eb4314ad` = the only fix the battery asked of CHARTS:
  `tests\autotest\run_feature_registry_families.ps1:58` now expects family default requires
  `index,graphviz` (powershell7 dropped with PS-free). Ran alone: PASS.
- Engine battery on 8d6df5ec was 692/4; the other 3 were engine/environmental (2 convert-apply
  under load, unused-unit-helpers waiting on the library-Win32 rebuild).
- Deployed from main: Win64 engine 1.31.4-alpha (11:04) + Win32/Win64 plugin BPLs. Installer built
  from main; the OWNER is testing it on a VM before publishing.
- The window is moving to a new Claude account (VS Code profile "DL"); hooks, skills, memory and
  this index are shared, nothing is lost.
- Prior handoff (now closed): [HANDOFF-2026-10-18-charts-ps-free-merged-wait](HANDOFF-2026-10-18-charts-ps-free-merged-wait.md).

## Resume point
Nothing is required. First optional action: retire the branch. This handoff commit sits on
`charts/ps-free` ABOVE the merged tip, so `git branch -d charts/ps-free` will refuse until it is
merged: get it onto main first (engine merges, or cherry-pick the docs commit), then switch the
worktree off the branch and `git branch -d charts/ps-free` (never -D without the owner).
Wait for the owner's VM result before any new charts round; the engine pings on failures.

## Not done yet (optional follow-ups)
1. Cap hint still DISPLAYS `-Cap N; raise -Cap` / `-SurfaceCap` (Ask.CapHow + Ask-Report.ps1:374).
   Switching to `--cap` touches ~12 expectations in ChartsTests.Question/Questions,
   tests\charts\fixtures\reports\who-writes.*, Test-AskReport.ps1:140 and the plugin's
   ReportTextTests.Cases.pas:197/265 -- change both sides for parity.
2. INBOX notes (object-leak on TArray<T>.Create; type-name-prefix with a library ancestor) are
   QUEUED on the engine side -- not ours.

## Gotchas
- `src/cli/_D-RAG/` is an untracked index artifact in this worktree; never commit it.
- Commit with a pathspec only; do not push (owner/engine publish).
- Test units are in no drag-lint index: Grep on tests\charts is an out-of-scope gap, logged.
