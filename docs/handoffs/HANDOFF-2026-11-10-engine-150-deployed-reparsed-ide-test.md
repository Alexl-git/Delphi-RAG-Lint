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