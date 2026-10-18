# HANDOFF 2026-10-18 -- charts -- PowerShell-free engine/installer

## Status
Branch `charts/ps-free` (worktree archify-ir), based on local main `cc6e9b09` (which contains
c7a82081). NOTHING COMMITTED YET -- all work is in the working tree. Engine session
(`delphi-rag-lint-a7`) is HOLDING the installer build until CHARTS reports "PS-free" (owner
request). Report to it again when done.

### Done in the tree (by the controller)
- `src\charts\DRagLint.Charts.Producer.PowerShell.pas` git-rm'd; removed from `src\cli\drag-lint.dpr/.dproj`.
- `DRagLint.Charts.Producer.Delphi.pas` rewritten: no fallback; `Create(pAllowLiveDb; pOutRoot)`;
  refuses unknown question / no index+no project with exit 2, unexpected exception with exit 1
  ("the in-process answer failed (Class: msg)"); EmitterScriptName deleted; a stray lone CR fixed.
- `DRagLint.Charts.Tools.ResolveChartsHome` (new; env `DRAGLINT_CHARTS_DIR`, then ..\charts,
  ..\..\charts\src, ..\..\..\..\charts\src, then the exe folder) replaces the Ask-Report.ps1 anchor;
  used by Producer.Delphi and Pairs.ResolveReportPairsFile.
- `QuoteArg` moved to `DRagLint.Charts.Process`; `TProduceOptions.TimeoutMs` removed.
- AskVerb.DefaultAskProducer = `TDelphiProducer.Create(True, pOutRoot)`.
- `--help` compare/ask lines (DRagLint.CLI.pas ~830/838) say in-process, no PowerShell.
- Plugin ReportText comment repointed to Process.pas.
- Tests: `ChartsTests.Producer.pas` + `fixtures\producer\Stub-AskReport.ps1` git-rm'd; new
  `tests\charts\ChartsTests.Process.pas` (QuoteArg round trip) registered in ChartsTests.dpr;
  3 ResolveChartsHome cases appended to ChartsTests.CoreTools.pas.

### Delegated (3 background sonnet implementers, edits only unless noted -- CHECK THEIR RESULT)
1. installer\drag-lint.iss (no *.ps1 shipped, pwsh detection/page removed), Build-Installer.ps1,
   VM-TEST-CHECKLIST.md, README.md, docs\AI-USAGE.md, hand-owned docs\wiki pages. Reports registry hits.
2. ChartsTests.ProducerDelphi.pas (fallback tests -> refusal tests) and ChartsTests.Compare.pas
   (in-Delphi TStubProducer replacing the PS stub); this one BUILDS + runs ChartsTests.
3. Regenerate hint (owner choice): `New-DiagramArtifact.ps1 -Question ...` -> `drag-lint ask <q>
   --target T --db "<db>" [--depth][--cap][--sql-db][--server-db][--counterpart-db][--surface-cap]
   [--control][--to]`; round-trip `drag-lint ask round-trip --target "<T>" --db .. --server-db ..
   --sql-db .. --depth N`. Changed IDENTICALLY in the PS reference (New-DiagramArtifact.ps1,
   Emit-RoundTrip.ps1) and Delphi (Ask.RegenerateText, Q.RoundTrip.Regenerate) so parity stays byte-exact.

## Resume point / next actions (in order)
1. `git status` + `git diff --stat` on charts/ps-free; review the three agents' edits (if the session
   was cleared, their reports are lost -- inspect the diff directly).
2. Build engine no-deploy (delphi-build skill, src\cli\drag-lint.dproj Win64 Debug); copy exe into
   the worktree's gitignored third_party\dll-win64 (guards read it). Build + run ChartsTests.
3. `charts\src\Test-Parity.ps1 -Mode Question` (0 diffs + positive control), run from repo root.
4. Guards: tests\autotest\run_docs_sync_guard.ps1, run_compare_verb.ps1, run_compare_real.ps1
   (it SKIPs on missing pwsh -- update its header/skip logic), run_feature_registry_guard.ps1,
   run_encoding_guard.ps1, run_extractor_version_guard.ps1 (no extractor change -> no bump).
5. Feature registry: chart-questions surface `script: charts\src\Ask-Report.ps1` -> use
   tools\feature-registry.ps1 to point it at `cli:ask`; then tools\build-feature-pages.ps1 -Normalise.
6. Reindex (`index --project src\cli\drag-lint.dproj --db src\cli\_D-RAG\drag-lint.sqlite`), then
   lint each changed unit + lint-all with `--enable magic-literal,multiple-statements-per-line,commented-out-code`
   incl. review-marker-stale.
7. Commit with explicit pathspecs (never -a / add -A); include the git-rm'd paths.
8. SendMessage `delphi-rag-lint-a7`: PS-free, branch + tip, ask them to merge (fast-forward on main) and build the installer.

## Gotchas
- `TProduceOptions.ScriptPath` now means "a file or folder in the charts scripts folder"; the repo's
  charts\src\Ask-Report.ps1 path still works as a marker in tests.
- charts\src\*.ps1 STAY as the frozen parity reference (not shipped, not called).
- Engine INBOX notes (not ours): compare --db missing from --help; quoted --command gets stray backslashes.
- PowerShell .NET calls use the process cwd, not the PS location: always full paths.

## Agent 1 (installer+docs) DONE
- Edited: drag-lint.iss (no *.ps1, pwsh page/InitializeWizard/ShouldSkipPage removed; Inno compile NOT run), Build-Installer.ps1, VM-TEST-CHECKLIST.md, README ~126, AI-USAGE 377/378/1282-1287, 25 docs\wiki\ask-*.md + Charts-and-the-IDE, compare, Diagrams-and-Charts, IDE-Menu-Reference, Setup-Installer, Field-Round-Trip-Report.
- Registry TODO (tools\feature-registry.ps1, then build-feature-pages -Normalise): drop requires powershell7 from entries\ask.json, compare.json, chart-questions.json, chart-engine-dot-lookup.json, families\chart-questions.json; compare.json:19 surface script Ask-Report.ps1; chart-questions summary + surfaces Ask-Report.ps1/New-DiagramArtifact.ps1. Generated blocks (AI-USAGE 762/769, Home/Features/Feature-Index/Quick-Help) follow from regen.
- Stale leftovers: docs\wiki\ask.md:83 ("Ask-Report.ps1 still works"), Charts-and-the-IDE ~68-73, Field-Round-Trip-Report ~154-157, ask-path.md:29.
- Encoding guard needs -Repo <root>; it flagged a lone LF in charts\src\Ask-Report.ps1 and tests\charts\ChartsTests.Compare.pas:722 (agent 2's file), BOM on 4 .dproj, dirs unaccounted (features rules skills SVG) -- check against main before blaming this branch.

## Agent 2 (test port) DONE
- ProducerDelphi: fallback tests -> UnregisteredQuestionIsRefused, UnexpectedFailureIsRefusedExitOne, CrossesBoundaryWithoutAnIndexIsSetup; 5 emitter/fallback tests removed. Compare: in-Delphi TStubProducer, FIXTURE_PROBE forms\a.csv.
- Run: `pwsh -NoProfile -File tests\charts\run_charts_tests.ps1` (repo root; builds via dcc64) -> 500 pass / 20 FAIL / 0 err. None in Compare/ProducerDelphi. Failures: CoreExceptions.NameFilterAndIndexStats, 11x Questions.TExceptionPathsTests, RoundTrip HoldoutMatchesPowerShell + GoldenMatchesPowerShell -- look like live-index counter drift (IndexRaise 168 vs 139). VERIFY against clean main before blaming the branch (the regen-hint change may also move the RoundTrip goldens).
- TODO: missing-explicit-ScriptPath test (exit 2 "the charts folder was not found"); ChartsTests.Compare.pas:722 lone LF (encoding guard).

## Agent 3 (regen hint) DONE -- UNVERIFIED (no build/tests)
- Delphi Ask.RegenerateText + PS New-DiagramArtifact.ps1:276 emit `drag-lint ask <q> --target T --db "<db>"` + same-order suffixes; round-trip Delphi Q.RoundTrip.Regenerate + PS Emit-RoundTrip.ps1:~100 emit `drag-lint ask round-trip --target "<T>" --db .. --server-db .. --sql-db .. --depth N` (FBundler/BUNDLER_SCRIPT/SCRIPTS_SUBDIR removed; target no longer quote-doubled).
- Extra: the raise-Cap hint parsed ` -Cap N` from the regen text; regex now ` --(surface-cap|cap) (\d+)` in Ask.pas (RE_CAP_ARG, CapHow) and Ask-Report.ps1:372. Hint still DISPLAYS -Cap/-SurfaceCap -- consider --cap/--surface-cap (parity: change both sides).
- Expected strings updated: ChartsTests.Question, CoreTraceFormA, tests\reportstext\ReportTextTests.Cases.pas:327, Test-RoundTripHelpers.ps1 (:137, :1076), Test-Emitters.ps1 (~1246/2291/2542/3298); goldens trace.plain.txt + 6 fixtures\roundtrip\*.dlgraph.
- Leftover callers of New-DiagramArtifact.ps1 (test-side): tests\plugin\run_reports_text.ps1, Ask-Report.ps1 -- fine as parity reference, but check run_reports_text is not a shipped-path test.
- All 3 agents done; next session starts at "Resume point" step 1 (diff review) then step 2 (build).

## CLOSED 2026-10-18
- Resumed and finished: the DERIVED-target parse (Q.RoundTrip TARGET_RX / Emit-RoundTrip.ps1:360) and stale test expectations were fixed on both sides; the 6 dot SHAs were re-pinned from the PS reference (a control reproduced the old pins); the registry entries point at cli:ask with no powershell7; lint findings fixed; two INBOX notes filed (object-leak on TArray.Create, type-name-prefix library ancestor).
- Left as a follow-up: the cap hint still says -Cap/-SurfaceCap (12 expectations + the plugin's ReportText test parse it).
