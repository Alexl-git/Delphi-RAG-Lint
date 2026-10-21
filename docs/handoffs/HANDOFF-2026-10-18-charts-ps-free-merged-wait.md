# HANDOFF 2026-10-18 -- charts -- PS-free committed, waiting on the engine

## Status
- PS-free work DONE: `charts/ps-free` @ `8d6df5ec` (one commit on local main `cc6e9b09`). NOT pushed --
  the owner publishes (engine said: do not push).
- Engine session `delphi-rag-lint-a7` took it: it fast-forwarded its probe worktree to 8d6df5ec
  (main has handoff commit e6566e72 above cc6e9b09, so main gets a real merge commit later). Its
  Win64 build was clean (1.31.4-alpha); it is running the full battery (~60 min), then the Inno
  compile, then the merge. It will message CHARTS only if something on our side fails.
- Verified here: ChartsTests 508/520 (12 = ExceptionPaths/CoreExceptions live-index stat drift,
  Index* fields only); Test-Parity -Mode Question 26/0 + controls; docs-sync, feature-registry,
  encoding, extractor-version, compare-verb, compare-real green.
- Details of the closed work: [HANDOFF-2026-10-18-charts-ps-free](HANDOFF-2026-10-18-charts-ps-free.md).

## Resume point
Nothing to do unless the engine reports a failure. If it does: fix on `charts/ps-free`, rebuild
no-deploy (`src\cli\drag-lint.dproj` Win64 Debug), copy the exe into the worktree's
`third_party\dll-win64`, rerun `tests\charts\run_charts_tests.ps1` and
`charts\src\Test-Parity.ps1 -Mode Question` from the repo root, commit with a pathspec, tell the engine.

## Not done yet (optional follow-ups)
1. The cap hint still DISPLAYS `-Cap N; raise -Cap` / `-SurfaceCap` (Ask.CapHow + Ask-Report.ps1:374).
   Switching to `--cap` touches ~12 expectations in ChartsTests.Question/Questions, the
   tests\charts\fixtures\reports\who-writes.* files, Test-AskReport.ps1:140 and the plugin's
   ReportTextTests.Cases.pas:197/265 (it asserts the text) -- change both sides for parity.
2. Engine-owned INBOX notes (C:\Projects\Delphi-RAG-lint\docs): object-leak on TArray<T>.Create;
   type-name-prefix "TInterfacedObject in neither index" (10 hits).

## Gotchas
- Test units are in no drag-lint index: Grep on tests\charts is an out-of-scope gap, logged.
- Dot SHAs in ChartsTests are pinned; re-pin only from the PS reference (scratch harness idea:
  Read-FormA + ConvertTo-TraceChart with the test's anchor maps, plus a control on the old fixtures).
- `run_charts_tests.ps1` and the engine msbuild share sources: run them one after the other.
