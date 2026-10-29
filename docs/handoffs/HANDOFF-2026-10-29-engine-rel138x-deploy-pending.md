# HANDOFF 2026-10-29 ENGINE -- rel/138x release candidate: lint verify, then deploy; then ORM3 hook supersede

Resumes/closes: HANDOFF-2026-10-29-engine-hang-fix-deploy-pending.md (hang fix DEPLOYED 10:06).

## Status
- Hang fix (fix/hang-int138 671cc9b3) DEPLOYED: dll-win64\drag-lint.exe + dll-win32/64 dclDragLintWizard.bpl/.dcp,
  hash-verified; main 3f848030 (BPL/DCP). Engine staged by RENAME-ASIDE (running image -> drag-lint.exe.old-100619,
  delete later -- needs approval); backups *.bak-pre-hangfix. Guards 49/54 (5 known fails, see Gotchas).
- Owner asked (2026-10-29): do all S items from "New today" in HPS, deploy, PREPARE a release (no tag/push/publish w/o go).
- Integration branch `rel/138x`, worktree `C:\Projects\Delphi-RAG-lint-wt\rel138x`, base fix/hang-int138. Merged:
  - fix/plugin-bounded-waits 92c9d0ad (ProcRun stand-down join 5 s -> detach; Editor sweep 30 min -> terminate; guard tests\plugin\run_plugin_bounded_waits.ps1)
  - fix/concat-in-loop-dynarray eefc23b2 (type-aware drop chases TArray aliases; INBOX note marked done, untracked)
  - feat/missing-uses-rule e5d842c6 (merge 9cfae071 of hang fix; codeAction guard run_lsp_missing_uses_code_action_guard.ps1)
  - 1b0b84e1 dropped stale dl:ok at CLI.pas DispImpls line; c2795e19 CHANGELOG entries in the 1.38.0-alpha section
    (DECISION: no version bump -- 1.38.0-alpha is still the unreleased owner-test build; v1.38.1 heading is reserved by the compat-downgrade plan).
- RC build (11:03) exit 0 engine + plugin Win32/Win64. Companions (sqlite3/tree-sitter dlls, casts.castlib) copied from
  dll-win64 + rules\ mirrored into src\cli\Win64\Debug (debug exe dies 0xC000007B without them).
- RC guards: 54/59 pass (5 known fails); feature-registry needed the plugin index at src\delphi-plugin\_D-RAG\dclDragLintWizard.sqlite (built).
- UNCOMMITTED in rel138x (lint fixes for the 5 changed-line findings):
  - `// dl:unit DRagLint.Lint.MissingUses accepted -- ...` on the uses lines CLI.pas:100, LSP.Server.pas:1373, LSP.Completion.pas:304 (uses-global-census, info)
  - `// dl:ok concat-in-loop -- Findings is a TArray<TLintFinding>...` on CLI.pas ~15496 (27 neighbouring Findings:= lines fire the same: rule cannot prove Findings non-string -> backlog item, not filed yet)
  - Plugin MissingUses.pas:37 used-unit-not-resolvable ToolsAPI: index-scope (designide not indexed; 31 identical pre-existing) -- left, justify in report.
- A re-lint was running in background: incremental reindex + lint-all of scratchpad\rel\lint\cli.sqlite -> cli2.lint.json.

## Re-lint result (12:2x)
Done: 1 finding left on changed lines -- CLI.pas:15496 review-marker-stale: the new dl:ok concat-in-loop carries no @hash. Re-mark it with the hash the lint message prints (full message in cli2.lint.json), re-lint that file, then step 2.

## Resume point (in order)
1. Verify the re-lint: scratchpad = C:\TEMP\claude\c--Projects-Delphi-RAG-lint\487fcb1b-6ff5-455e-8e0b-5b5450070ebc\scratchpad\rel ;
   `& "$r\changed_lint.ps1" -Json @("$r\lint\cli2.lint.json")` must show 0 on changed lines and no review-marker-stale/unused
   for the new markers (if cli2.lint.json is empty/partial, rerun lint-all on that DB with
   --enable magic-literal,multiple-statements-per-line,commented-out-code,review-marker-stale,review-marker-unused --json).
2. Commit the 3 files in rel138x with pathspecs (src/cli/DRagLint.CLI.pas src/lsp/DRagLint.LSP.Server.pas src/lsp/DRagLint.LSP.Completion.pas).
3. Rebuild engine + plugin: `$r\run_eng.bat`, `$r\run_plgWin32.bat`, `$r\run_plgWin64.bat` (Start-Process -Wait; logs $r\*.log, BUILD_EXITCODE=0). Re-copy rules\ if changed.
4. Deploy (check `Get-Process bds` -- BPL needs RAD Studio closed): rename-aside dll-win64\drag-lint.exe -> .old-<hhmmss>, copy RC exe;
   copy BPL+DCP Win32/Win64 to third_party\dll-win32|dll-win64 (backup *.bak-pre-rel138x); robocopy rel138x\rules -> third_party\dll-win64\rules (NO /MIR);
   hash-verify; commit BPL/DCP on main with pathspecs. FYI lsp-a2, www-9b, convrules-editor-c8.
5. Release prep (no publish): merge rel/138x -> main only on owner go? (main is 1.36-era per earlier handoff; ask). Re-verify article
   WWW\articles\2026-10-29-add-the-missing-uses-unit\index.html vs the deployed exe (delegate, sonnet). Release-day duty: draft product-intro + feature article, message www-9b.
6. DROPPED by owner ruling 12:xx: commit reindex hook DISABLED in ~\mercurial.ini (backup .bak-20261029-noreindex); IDE/LSP rescan on save, agents reindex after edits. ocrpdf-e5 told. Old text: ORM3 hook SUPERSEDE (promised to ocrpdf-e5, due today): C:\Users\alexanderl\hg-hooks\orm3_reindex.py currently SKIPS when the
   lock PID is alive. Change: on a live lock ask the old indexer to stop cleanly (1.38 control channel; find the exact verb in
   `drag-lint --help` -- shutdown/ide-release family), kill that PID after 30 s, take the lock, start fresh. Test with two quick runs; log.
   Reply to ocrpdf-e5 when done. (Already told them: Q3 = yes, rows keyed by file_id, incremental re-emits per unit; no schema change.)

## Not done / backlog additions
- concat-in-loop: `Findings:= Findings + F(..)` in CLI.pas lint dispatcher (27 lines) still fire -- file INBOX (rule cannot type the local/param).
- Plugin worker-loop INFINITE waits JobQueue.pas:664, LspWriteQueue.pas:298 (teardown signals them; low).
- feat/index-fill-prop-types 54ca1379 (committed, NOT merged; retires `hover --write-back`, exit 3) -- next wave.
- Housekeeping (owner approval): delete dll-win64\drag-lint.exe.old-100619; worktrees s-waits, s-concat, hangfix, rel138x after merge;
  junk C:\Projects\DB\ORM3\drag-lint.sqlite (2 GB).
- ConvRules findings on conv/dlggap lines (CONVERTER told): Engine.pas:1708, CurationForm.pas:39.

## Gotchas
- Known pre-existing guard fails (also on deployed 1.38): run_lsp_full_rules, inlay_hint, switch, switch_params, switch_vscode.
- run_feature_registry_guard takes -Engine (not -Exe) and needs the plugin index inside the worktree.
- run_encoding_guard fails on any untracked scratch dir inside a worktree -- keep scratch outside.
- docs-sync probe control flakes under CPU load (20 s timeout) -- rerun.
- stage-engine.ps1 KILLS every holder of the image; with peers running use rename-aside instead.
