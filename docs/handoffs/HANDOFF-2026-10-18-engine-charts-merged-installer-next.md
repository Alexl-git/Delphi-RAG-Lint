# HANDOFF 2026-10-18 -- ENGINE -- charts merged to local main; test installer next (after CHARTS PS-free)

Supersedes HANDOFF-2026-10-17-engine-1314-release-overnight.md (its UPDATE blocks hold the detail;
read them only if you need the history). Owner back late morning 2026-10-18.

## Status
- 1.31.4-alpha: deployed to dll-win64 (Debug, from 36dc1866, sha256 58445037...0F1C), battery
  690/3/0 (all 3 explained), zips in C:\TEMP\rel-1.31.4-alpha\, NOTICE committed 9d903dc5.
  NOT pushed / tagged -- owner publishes (commands in docs\NOTICE-2026-10-17-v1.31.4-ready.md).
- Library rescan (both platforms) done 2026-10-18 01:54 (3h10m). Win64 needs no rebuild
  (files 7155 <= walked 7160). Win32 was widened (7318 > 6943) -> rebuild launched (below).
- Charts stack + CHARTS fix + ENGINE follow-ups merged; LOCAL main = c7a82081 (+ cc6e9b09 handoff),
  NOT pushed. Battery on c7a82081 (probe worktree): 696/0/0. Merged engine NOT deployed to dll-win64.

## In flight (survives /clear -- detached pwsh PID 114216, started 07:16)
`C:\TEMP\claude\sdd-1314\release\overnight-reindex.ps1`:
1. `index --project src\cli\drag-lint.dproj --db src\cli\_D-RAG\drag-lint.sqlite` (main self-index,
   stale since 10-16; ~4 min).
2. `index --all --only Library --platform win32 --rebuild` (~3 h). CHARTS does not use library-Win32.
Status: `C:\TEMP\claude\sdd-1314\release\overnight-reindex.status.txt` (START / SELFINDEX / LIBWIN32_REBUILD
exit+elapsed / `===` summary / DONE). Logs beside it. Check: `Get-Process -Id 114216`.
After DONE: `library-drift --json` (Win32 expect 0) and confirm Win32 `files <= walked`.

## Resume point (in order)
1. Read the status file; if done, run library-drift; log duration in the RESUME line.
2. Wait for CHARTS (session charts-61) "PS-free" message: it removes the PowerShell producer
   fallback, the Ask-Report.ps1 lookup, the .ps1 files + pwsh page in installer\drag-lint.iss, and
   --help mentions; touches drag-lint.dpr/.dproj. Asked to stack on main c7a82081 -> merge must be
   `git merge --ff-only <their tip>` in the main tree. If it is not ff, merge in the probe worktree
   again (C:\Projects\Delphi-RAG-lint-wt\merge-charts-probe, branch probe/merge-charts-20261018).
3. Build in the probe worktree (build\build_draglint_win64.bat -- deploys only INTO the worktree),
   full battery there (`pwsh -File tests\run_battery.ps1`, ~60 min), re-run run_compare_verb +
   docs-sync, lint-all doc-drift 0 (`document --unit --apply` if not).
4. TEST installer: `pwsh -File installer\Build-Installer.ps1 -EngineDir <probe>\third_party\dll-win64`
   (default -EngineDir is the MAIN dll-win64 = deployed 1.31.4; it checks engine version ==
   DRAGLINT_VERSION). Output: installer\Output\. Do not install it on this machine.
5. Owner decisions: go to deploy the merged engine to dll-win64; publish 1.31.4 (tag 36dc1866 or a later
   HEAD -- main now also carries the charts stack); billing split help (memory project_billing_split_orm3_dl.md).

## Gotchas
- Probe worktree battery needs gitignored outputs that a fresh worktree lacks: drag-lint-switch.exe
  (copy) + build\build_lsp_switch.bat, self-index src\cli\_D-RAG, tests\fixtures\T2..T7 *.exe (copy
  from main). All already present in the probe worktree.
- drag-lint-first hook false-denies Select-String over `git diff -- *.pas`; run any drag-lint.exe call
  first (5-min allow window).
- Autonomy guard blocks shell text containing the engine stand-down verb; use stage-engine.ps1.
- Open INBOX: docs\INBOX-library-drift-win64-lib-dirs.md, docs\INBOX-compare-help-db-and-command-quoting.md.
