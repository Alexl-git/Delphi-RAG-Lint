# HANDOFF 2026-10-18 -- ENGINE -- 1.31.5 merged + installer built; owner gates remain

Supersedes HANDOFF-2026-10-18-engine-wave-1315-lanes.md (closed). Autonomous run 20261018-1805.

## Status
- main 34175807 = merge of wave/1315 (9 lanes + release prep 750b8f41 + battery follow-ups
  ea427ef9); 80576166 adds docs\NOTICE-2026-10-18-v1.31.5-merged.md. main is 34 commits ahead of
  origin, NOT pushed.
- DRAGLINT_VERSION 1.31.5-alpha; CHANGELOG v1.31.5-alpha section written.
- Extractor 1.21.1 and resolver 1.12.0 NOT bumped; both baselines re-pinned with written reasons
  (lane 1 binary-DFM raw-byte check; lane 2 scoped-pass bookkeeping).
- Battery (wave worktree, @750b8f41): 699/709. 10 failures = 2 real (resolver re-pin; allow --help
  missing the lint options lane 7 made it read -> fixed ea427ef9, flag-verb baseline 112 -> 110),
  7 worktree-environment (untracked LspStubServer.exe, calls.sqlite, lsp-switch exe, src\cli self-index,
  T2-T7 fixture exes -- copied/rebuilt into the worktree), 1 transient (magic-literal.pas). Rerun of
  all 10 + docs-sync + extractor guard: 12/12 green on the rebuilt engine.
- Installer: installer\Output\drag-lint-setup-1.31.5-alpha.exe (29.9 MB, 2026-10-18 20:04), built
  from the wave worktree: engine + drag-lint-config.exe (Win64 Debug) + plugin BPLs Win32/Win64 built
  from wave source; drag-lint-switch.exe, ConvRulesEditor.exe, drag_lint_graph.exe copied unchanged
  from the shared dll-win64 (no source change in the wave).
- Lane-10 INBOX: B-04/B-09/B-15/B-32 retired to docs\INBOX-Done; B-16 stays open (bare-call half
  rides 1.22); INBOX-INDEX recounted 67/42/346 -- backlog-index guard PASS (untracked files).
- YADF session told (B-06 ends its doc rewrite loop). CONVERTER/CHARTS were not live: the NOTICE file
  is their notification.

## Resume point (all owner-gated)
0. DONE 2026-10-19 on owner 'go': engine 1.31.5 (sha 201DE760) + drag-lint-config.exe staged to dll-win64 (.bak-1.31.4 kept); BPLs Win32+Win64 deployed, commit 693ae603. Step 1 below is complete.
1. Owner "go" -> deploy engine then BPL (RAD Studio closed): engine via
   `build\stage-engine.ps1 -FreshExe <wave-1315>\third_party\dll-win64\drag-lint.exe -Target
   third_party\dll-win64\drag-lint.exe`; BPLs from `<wave-1315>\third_party\dll-win32|dll-win64\
   dclDragLintWizard.bpl/.dcp` into main's third_party (tracked -> commit "deploy: 1.31.5 plugin BPLs").
   Also stage drag-lint-config.exe from <wave-1315>\third_party\dll-win64 (Config Save fix B-22).
2. Owner VM test of the 1.31.5 installer (installer\VM-TEST-CHECKLIST.md).
3. Owner: `git push` main, tag v1.31.5-alpha, publish the installer only (gh release create).
4. Cleanup (needs approval): worktrees `.claude\worktrees\wave-1315`, `agent-*` lane worktrees,
   broken `agent-a093407ae7ae356a5`; branches fix/1315-*, wave/1315.

## Not done / next wave
- Wave 2 list: docs\superpowers\plans\2026-10-18-bugfix-wave-1.31.5.md (gitignored) + lane follow-ups:
  lint --fix --apply without --project-rules skips doc-drift fixes; 'declaration' as a Used-by caller;
  YADFOT new DB 162/174 outside closure; watch-mode FScopeWhole latch never reset; prune ids counted
  as changed.
- CHANGELOG "Unreleased" block holds charts work already shipped in the 1.31.4 tag -- owner to decide
  whether to fold it into v1.31.4.
- 1.22 extractor release (all teams, ~5 h re-parse) -- add Analysis.Flow.Lattices.pas to the hash
  surface then (lane 8 symbol_facts change).
- CLI.pas help-string edit (ea427ef9) was not separately linted (string-only change).

## Gotchas
- The wave worktree's untracked artifacts (self-index, fixture exes) exist only there; a fresh
  worktree battery shows the same 7 environment failures. Guards default -Exe to the worktree path.
- Main checkout's tracked BPLs are still 1.31.4; the rebuilt BPLs sit UNCOMMITTED in the worktree.
- stash@{0} is the owner's -- keep.
