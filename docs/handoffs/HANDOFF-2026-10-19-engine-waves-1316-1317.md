# HANDOFF 2026-10-19 -- ENGINE -- waves 1.31.6 + 1.31.7 merged on integration branches; battery running

Supersedes HANDOFF-2026-10-19-engine-wave2-start.md (resumed). AUTONOMOUS run `20261019-0355-engine`
(`~\.claude-dl\autonomy\mode.json`). Owner orders (2026-10-19): finish 1.31.6, commit AND push
(push is hard-blocked while autonomous -> owner step), then fix the remaining known bugs + B-02,
B-18, B-24, then STOP for owner reassessment. Delphi 13.2 is installed. 1.22 extractor release
stays HELD (not in the order). No publish / deploy in this run.

## Status
- Plans: `docs\superpowers\plans\2026-10-19-bugfix-wave-1.31.6.md`, `...\2026-10-19-bugfix-wave-3.md` (gitignored).
- `wave/1316` (worktree `C:\Projects\Delphi-RAG-lint-wt\wave-1316`, tip 6a37ac33): lanes A-F merged,
  version 1.31.6-alpha, CHANGELOG, README/Home/manifest committed. All lane guards PASS.
  Own fix e88a94b4: run_format_verb_guard A6 SKIPs when the Debug YADF (now 1.0.20.0) is not below the 1.0.6.6 floor.
- FULL BATTERY on wave/1316 RUNNING (started ~04:00, ~716 runners, ~2 h; 282/716 0 FAIL at ~05:00).
  Log: `C:\TEMP\claude\c--Projects-Delphi-RAG-lint\2603001c-e252-413c-849b-21b771f34058\scratchpad\wave\battery2.txt`
  (per-runner logs in `...\wave\battery2\`). If the session died, the run may have died with it --
  check the tail; re-run `pwsh -File tests\run_battery.ps1 -LogDir <dir>` from the wave-1316 worktree if incomplete.
- `wave/1317` (worktree `C:\Projects\Delphi-RAG-lint-wt\wave-1317`, from wave/1316, tip 962519a0):
  lanes G, H, I, J, K, L ALL merged + 1.31.7-alpha bump/CHANGELOG/README/Home/manifest (tip after lane G: see git log). Exe reports 1.31.7-alpha; lane guards PASS. Engine + BPL Win32/Win64 build
  EXIT 0; lane guards + docs-sync/registry/encoding/extractor-version PASS. Uncommitted in that
  worktree: rebuilt plugin BPL/DCP under third_party\dll-win32|64 (tracked deploy artifacts; leave
  for a separate deploy commit, owner "go").
- Lane G (`fix/1317-g-usages`: `usages` field reads 0 for TDragLintJob.Streaming / TArgs.Watch;
  B-21 outline no-DB error on stdout) was STILL RUNNING at checkpoint. Its worktree:
  `C:\Projects\Delphi-RAG-lint\.claude\worktrees\agent-ac663cbea1e4e5553`. Check `git log wave/1316..fix/1317-g-usages`.

## BATTERY RESULT (wave/1316, finished): 712/716 PASS, 4 FAIL -- run_flag_verb_map, run_lsp_switch_guard, run_resolver_version_guard, run_doctests_v021 (366 s). Per-runner logs: scratchpad\wave\battery2\. Triage each against the deployed 1.31.5 engine / main FIRST (pre-existing vs wave regression); lsp_switch may be the battery-prerequisite exe (lane F prepare_battery). Do NOT merge to main until each is explained or fixed.

## Resume point (in order)
1. Battery on wave/1316: read the tail of battery2.txt. Any FAIL: compare against main's deployed
   engine before blaming the wave (A6 lesson); fix on wave/1316, re-run that runner.
2. Battery green -> `git -C C:\Projects\Delphi-RAG-lint merge --no-ff wave/1316` on main (main has the handoff commit 73880364 on top of 2681941b, so not a fast-forward). Tag nothing.
3. (DONE: lane G merged, guards PASS.) Was: lane G: if committed, merge into wave/1317, add its CHANGELOG lines under v1.31.7, rebuild
   (`...\scratchpad\wave3\b.bat`), run its guard + docs-sync. If unfinished/abandoned, list G's items
   as open for the owner.
4. wave/1317: rebuild, `tools\build-feature-pages.ps1 -Normalise` (Home/manifest take the version
   from the built exe), commit, full battery once, then merge wave/1317 into main (--no-ff).
5. INBOX hygiene in the MAIN checkout (gitignored): notes for B-02 (INBOX-library-drift-win64-lib-dirs.md)
   and B-18 (INBOX-2026-10-05-freshness-misses-edited-dfm.md) were set to `status=fixed`, B-24
   (INBOX-index-stage-list-copies-skip-facts-inherited.md) to `fixed-on-branch` -- NOT valid for
   run_backlog_index_guard ($VALID = open, parked-owner, parked-ide-bound, parked-extractor-batch,
   blocked-repro, ideas). After merge to main: set `status=retired`, Move-Item into docs\INBOX-Done\,
   update INBOX-INDEX.md counts (line 1 dl:counts, "BACKLOG INDEX -- N notes" ~l.73, status table
   rows, "INBOX index -- N notes" ~l.153) until the guard PASSes.
6. Set mode.json phase "complete" (or "handoff"/owner-decision), report to owner. Owner steps: `git push`
   of main; publish/deploy 1.31.6/1.31.7 if wanted.

## New findings for the owner's reassessment (not fixed)
- `rename --qname` of a FREE function does not rename its implementation header (lane I probe; medium).
- lint --fix multi-project rename and MCP `rename_symbol` lack the new .inc refusal.
- reconcile heal + BuildPlanItem call ResolveCallTargets without library stores (DoIndex passes them) (lane L).
- IndexDictionary is dead code (still in run_migrate_site_guard's exempt list).
- Owner decision: index Win64 compiled-lib .dfm like Win32? Needs the "Win64" global exclude changed + a library rescan; that exclude also prunes Win64 SOURCE folders (lane J).
- Lane J re-pinned tests\extractor-version.baseline WITHOUT a version bump (Indexer.pas refactor, walk unchanged) -- review.
- Lane H item 1 closed as by-design: `allow --fix-line` drops the REVIEWED stamp deliberately (guard L3/L3b); owner may reverse.
- B-13 parked to the 1.22 extractor batch (no ref for member on index-expression receiver).
- `usages` 0 reads for fields (lane G, if unfinished); `context` callers of TRoutineVarTable.Build list other classes' Build.
- Agent worktrees have no index -> each lane builds a private DB (~3 min) or falls back to Select-String; worth a "worktree index" recipe.
- B-21 / B-25 backslash strip: review at whole-branch review.

- Lane G: `Result.Streaming := False` (IndexJob.pas:121, Reports.pas:365) never bound (symbol_id NULL, no member_accesses row) -- resolver gap for the 1.22 batch; logged to draglint-gaps.log, INBOX note NOT filed yet (file it). `usages --width wide` CLI vs LSP `very-wide` mismatch; `impact` no-args usage + `slice` not-found lines still on stdout.

## Gotchas
- `build\build_draglint_win64.bat` deploys to `%ROOT%\third_party\dll-win64` of the tree it runs in
  -- safe in a worktree, NEVER run it in the main checkout without owner "go".
- Do not rebuild a worktree while its battery runs (a build kills a running measurement).
- stash@{0} is the owner's -- keep. Agent worktrees under `.claude\worktrees\agent-*` (11) can be
  removed after merge (unlock first if locked).
