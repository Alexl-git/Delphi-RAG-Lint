# HANDOFF 2026-11-10 (~13:30 CST) -- ENGINE -- 150 deployed + re-parsed; owner IDE test next

Previous: HANDOFF-2026-11-09-engine-150-wave-running.md (closed).

## State
- main = a3aea3675 (LOCAL, unpushed): 150 integrated (INT DONE 8369857b7, schema 24, extractor 1.35 / resolver 1.23 re-pinned once), CLAUDE.md parse-errors note 09f99cfea, dll-win32 config f63ab222f, H1 guard hygiene + DOC3 changelog + MS-B measurements merged.
- Deployed: dll-win64 drag-lint.exe 1.49.0-alpha (SHA 2EA90262...7679), grammar DLL v1.4.9, plugin BPL Win32/Win64 (fcd91bba1), drag_lint_graph.exe with text nodes (Graph repo main 21a7b84, unpushed), installer re-staged.
- Re-parse DONE: libraries W32 6966 (parse-errors 19), W64 7162 (48); 37/37 project sections parse-errors 0.
- Battery: 1328 pass / 5 skip / 19 fail -> 12 guards fixed, 4 flakes, 3 env (now fixed by H1).
- Owner page (tests + every open item with effort): https://claude.ai/artifact/QWrmj65xP1U3hFX31mtLsK (source C:\TEMP\claude\lanes\150\DL-150-TESTS-AND-LEFTOVERS.html).
- Disk: C: 176 GB free after cleanup (C:\TEMP lanes 143-150 worktrees/binaries removed; reports/ledgers/staged kept; saved diffs in C:\TEMP\claude\lanes\_saved-diffs-20261110).

## Next action
1. Owner: reboot, then IDE/VS Code/VM tests from the page (Part A); then push main + release 1.49.0-alpha.
2. After release: post C:\TEMP\claude\lanes\150\POST-AFTER-1.49\ replies (GitHub #13, PR #3 + close), grammar v1.4.9 master/tag/npm (owner).
3. First engineering item after release: docs\INBOX-table-tools-field-repository.md (ORM3 request), then Table Tools.
4. Next wave (needs a re-parse): page Part B section 1 (resolve x1.23 in calls stage, LogError unbound x150, FindPropInfo, returns_owner order, RS2 OFF switch, library-D5 source root, DRAGLINT_PP_TRACE).
## Update ~14:15 -- DFM grammar DLL regression found by owner's C0 test (RESUME HERE)
- Deployed third_party\dll-win64\tree-sitter-dfm.dll was the OLD July v1.1 build (22016 B) instead of the committed v1.2.0 (d11f115d1, 28672 B, git blob ea3b5b4f). RESTORED at ~14:05 from C:\TEMP\claude\lanes\150\_base-engine (== HEAD blob); git status clean; old copy kept as C:\TEMP\claude\lanes\150\DEPLOY\tree-sitter-dfm.dll.old-0716. Cause not found yet (deploy build.log silent; several 22016-B July copies exist in tests\fixtures, tests\refactor, charts\scratch\probe, engine-pinned\*).
- Consequence: today's re-parse extracted .dfm facts with DFM grammar v1.1 (no non-ASCII identifier fix, Y2 dfm_nav tables from v1.1). `info` still says verdict: current -- the DFM DLL is NOT in the index fingerprint, so an incremental reindex will not redo them.
- NEXT ACTION (pending): owner go + ORM3 all-clear (orm3-f7 asked to hold until its Task 10 subagent finishes reindexing COMMON/SERVER, ETA ~15:00; it will message). Then forced rebuild of the 37 project DBs only (tools\reparse-libraries.ps1 project phase or `index --all --rebuild` per project section, libraries skipped; ~1 h). Then owner reboot + IDE test (page https://claude.ai/artifact/QWrmj65xP1U3hFX31mtLsK, local copy C:\Projects\DL-150-TESTS-AND-LEFTOVERS.html; C0 passed).
- Next wave items added: put the DFM DLL hash into the index fingerprint; find the step that copied the old DLL; deploy check that every third_party file equals git HEAD.
## Update ~14:30 -- cause found + guard committed (4ea0f0e0f)
- CAUSE: 11-09 12:34 `git merge --ff-only lane/149-INT | Select-Object -Last 3` aborted on "unable to unlink old third_party/dll-win64/tree-sitter-dfm.dll" (loaded by a running engine) after writing 213 files; error hidden by the filter; main then moved by `git update-ref` + index reset, so the old DLL stayed. Reproduced in a scratch repo.
- DONE: build\check-thirdparty-head.ps1 (tracked *.dll in dll-win64/dll-win32/dll == HEAD) called by build_draglint_win64.bat and reparse-libraries.ps1 (default engine); guard tests\autotest\run_thirdparty_head_guard.ps1 7/7 with positive control; encoding guard PASS.
- 39df9242e: S1 'flake' was real -- run_pipeline_tests + run_schema_read_compat wrote lint-report-<date>.txt into the repo root; fixed, hygiene guard now watches the root. Other 3 flakes = -Jobs 6 timing.
- Owner chose option C (detect, not invalidate): lane/151-GD 8d018c075 (worktree C:\TEMP\claude\lanes\151\GD\wt, NOT merged/deployed): schema_meta grammar_dlls + info grammar_dlls_differ; guard run_grammar_dlls_stamp_guard.ps1 GREEN 8/8, RED 7/8 on 1.49. Owed at integration: lint-all, featuregen entry for info (grammar_dlls fields), wiki/AI-USAGE mention.
## Update ~14:20 -- ORM3 ALL-CLEAR received (RESUME HERE)
- orm3-f7: Task 10 committed (COMMON rev 40 2effe47, SERVER rev 47 5e11236); no ORM3 drag-lint writes until our rebuild is done.
- NEXT ACTION: on owner go -> forced rebuild of the 37 project DBs (libraries skipped, ~1 h). Then owner reboot + IDE test. Then MESSAGE orm3-f7 (rebuild + IDE tests done) -- it runs CPU benches needing an idle box. Then push main + release 1.49.0-alpha.
- Lane 151-GD (option C) is DONE on its branch, waits for the next wave; nothing to do for it now.
## Update ~14:50 -- forced project rebuild DONE (RESUME HERE)
- Owner go 14:35. `index --all --only <37 sections> --rebuild --jobs 4 --rule-cache-warm off` (libraries skipped) 14:36:45-14:48:03, EXIT=0; 37/37 sections attempted=committed, parse-errors=0. check-thirdparty-head OK before the run. Logs C:\TEMP\claude\lanes\150\rebuild-projects\.
- VS Code extension engines (Code-dl, Code-gmail) were left running (own engine copies, read-only). `shutdown --all` is refused by the autonomy hook (matches 'shutdown'); ide-release hold lifted after the run.
- NEXT ACTION: owner reboot + IDE test (page QWrmj65xP1U3hFX31mtLsK). Then MESSAGE orm3-f7 (rebuild + IDE tests done). Then push main + release 1.49.0-alpha.
## Update 2026-11-11 ~00:55 -- VS Code fixed, owner testing Part A (RESUME HERE)
- Reboot done 11-10 18:45. VS Code: DL profile registered drag-lint 1.6.0 at a deleted folder (never loaded); default profile had 1.6.2 + engine copy from 10-27. Extension 1.6.4 packaged (e0b122aa9; 1.6.3 vsix lacked 148 VS + 149 LX) and installed into both profiles; activated 00:48, engine copy hash-equal to deployed 1.49 exe + 3 tree-sitter DLLs. check-thirdparty-head OK.
- Owner page republished (v3): status box, V0 PASSED, C15, new backlog rows (silent stale extension, package-lock drift, 151-GD owed items).
- NEXT ACTION: owner runs Part A. Then MESSAGE orm3-f7 (rebuild + IDE tests done). Then push main (198 ahead) + release 1.49.0-alpha + vsix 1.6.4 on go.
