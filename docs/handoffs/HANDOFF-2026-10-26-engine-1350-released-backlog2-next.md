# HANDOFF 2026-10-26 ~00:30 -- ENGINE -- 1.35.0-alpha released + re-parsed; backlog section 2 next

Controller `delphi-rag-lint-65`. Resumed `HANDOFF-2026-10-25-engine-cyc-merged-battery-deploy-next.md` (now closed).
Ledger: `.superpowers\sdd\2026-10-23-engine-3day\progress.md` (rows "RELEASE 1.35.0" and "REPARSE DONE" at the bottom).

## Status (all done and verified)
- Battery on 25a49425 was 848/11. A serial rerun showed 2 of the 11 were parallel-only flakes. Six were stale guards, fixed in ca439aa5 with no engine
  regression: docrules 137->138 (line-too-long), lint-store circular-uses anchor line 9, json_stdout without --output,
  lint_all_output -NoEnumerate array, no_default_db --exact, resolver-surface EXCLUDE GetUnresolvedCallsFromSymbol.
- 072cf4ea: the 2 cyc1 lint fixes. a51bef32: CONV-ENC merged (72/72 targeted green on a fresh build).
- 1610c1fd X batch: X1 X2 X4 X5 X6 merged, ONE bump: extractor 1.24.0-alpha, resolver 1.14.0-alpha, DRAGLINT_VERSION
  1.35.0-alpha, 194 rules (new: enum-bare-read-scoped, platform-divergent-define, enum-ordinal-persisted). The CHANGELOG v1.35.0
  section folds in CONV-ENC. Full battery on that branch: 860/6, all 6 explained (3 known reds, 2 parallel flakes, exe_freshness).
- DEPLOYED to dll-win64 (owner-authorised) and PUSHED origin/main. Main has since moved to e75d2156 (www) and is in sync.
- RE-PARSE DONE 21:55 on 10-25: library-Win32 files=6938 + 36 project DBs (37/37 OK, 8.7 h); library-Win64 files=7155 (9.0 h).
  The re-parse-done message went to convrules-editor-31, www-5b and lsp-4e. www-5b articles name 1.35.0 and are published.
- DUnitX root: NO edit needed. Both library DBs already hold 92 DUnitX files via `"source": "registry-libraries"`
  (Index.Plan.pas:341, so an include list there is ignored).
- Repo audit (owner request via www-5b) was reported to the owner. Converter branches feat/converter-model-batch,
  feat/converter-apply-fields, fix/converter-testkit and feat/conv-qualify-d4-n2 are SUPERSEDED (squashed into faffc407 / d7a289ba
  and cherry-picked as dea6c6f4, all on origin/main). fix/featuregen-fgo-fgp + helporder-tiebreak are patch-equal on main.
  X-lane bump branches (a08b3329, a5dd69f2, a6b55823, a7205be6, acc26006) are superseded by 8ccbd06f.
  Branch/worktree DELETION awaits the owner's go (not given). Unmerged on purpose: worktree-agent-ae49d9f476c2d9426
  (= W6-flagmap 909fc131, owner: rework, do not merge) and archive/feat-converter-editor.

## Next actions, in order
1. Small owed items: retire INBOX `local-var-read-refs-unbound` (move to INBOX-Done, header closed, backlog guard);
   re-verify the registry entries that were verified against the stale exe (lsp, menu-tree, ide-help-line, f2047) on 1.35.0
   (`featuregen verify --id <id> --by ENGINE` only for ENGINE-owned entries).
2. Backlog section 2 = the owner rulings ~11:00 on 10-25, verbatim in `HANDOFF-2026-10-25-engine-cyc-merged-battery-deploy-next.md`
   "OWNER RULINGS ~11:00", brief `docs\superpowers\plans\2026-10-25-owner-questions-brief.md`. Run as parallel lanes
   (owner: multi subagents):
   a. T-22 unit completeness: a NEW DL command + IDE menu entry, part of lint-all, with an autofix listing used units that are in
      neither the project nor the library. Fix options: DEFAULT = add the unit to .dproj+.dpr; ALT = add its folder to the library path.
      Check what exists first (`lint --rule unit-not-in-dpr`, `reconcile-project --apply`). Then TDD, featuregen entry, wiki, menu path;
      APPLY it to MicroniteTests + PdfOcrImportTests, rescan and report. FlexDateTime + MSCTYPES = project units.
   b. Flag-alias policy: one written policy (canonical + aliases, how help shows them). Update featuregen + the docs-sync /
      flag-verb-map scanner, and rework lane ae49d9f4/909fc131 to match. Fixes the known red run_flag_verb_map (+--apply +--fix).
   c. entryunitkey: `Used in units:` must hold units only. Add a `Used in classes:` line (TDFMParser, TFirebirdSqlParser),
      make the doc tool accept it, and find and stop the generator defect.
3. Then backlog 2 rest: cycles C2/C4/C6/C7, B3/B4 (after the Task-17 F2092 check), A2 --apply/.dpk, plugin CCycleFixTimeoutMs
   +10 min, X-26 per-verb help, the CONV-ENC follow-up INBOX (lossy non-ANSI identifiers). Then section 3 (hygiene).
   Source list: `docs\superpowers\plans\2026-10-25-engine-backlog-full.md`.

## Known reds (not regressions)
run_flag_verb_map (-> 2b), run_featuregen_tests frozen banner (CONVERTER), run_reviewmarker_yadf_mirror (env).
Flaky under -Jobs 6: run_uses_fix_json_and_only, run_uses_fix_include_skip, run_procrun_jobs (green serially).

## Gotchas
- The battery script is `tests\run_battery.ps1` (not tests\autotest). Guards lint_all_output + no_default_db need
  -DbPath/-RealDb in a worktree with no engine DB.
- cmd quoting via Start-Process breaks on nested quotes: write a wrapper .bat in the scratchpad (rsvars/build bat > log).
- `git cherry` shows squashed work as unmerged. Check the squash messages before calling a branch lost.
- dll-win64 deploy: `drag-lint ide-release --seconds 900` + `shutdown --all --wait 30`, then build_draglint_win64.bat.
