# HANDOFF 2026-10-27 -- LSP: release roll-up done, owner/IDE items left

Session lsp-52. ENGINE = delphi-rag-lint-65 (merge owner; release = 1.37.0-alpha, staged at INT).

## Status
- All LSP code for the release handed to ENGINE; ENGINE merged to LOCAL main (unpushed, ENGINE pushes):
  - fix/lsp-switch-release 4a2d2be6 -> main 64f7b4dd: build_draglint_win64.bat + pack-lint-release.ps1
    build/stage/ship drag-lint-switch.exe (deployed copy was 2026-08-19, lacked --params); stage-engine.ps1
    matches holders by image name; guard run_release_ships_switch_guard (12/12).
  - fix/help-out-json 49b6402c -> main 84bbd47c (909fc131 redo; flag-verb baseline 107 -> 104).
  - fix/help-compare-out-root 8503841c -> merged (compare --out-root on help; baseline 104 -> 103).
  - fix/lsp-unowned-label ca91e559 -> main 9aa87e94 (ENGINE, CHANGELOG conflict resolved; resume step 1 DONE).
    Diagnostics of a file no index owns get source "drag-lint (unowned)"; guard
    run_lsp_unowned_label_guard (RED on 1.36.0, GREEN 5/5); run_lsp_full_rules_guard adjusted.
- fix/lsp-clear-diags-on-close f719c702 + 6cc58823 (worktree .claude\worktrees\lsp-cleardiag): owner bug --
  Problems kept warnings of closed/deleted files. didClose and workspace/didChangeWatchedFiles (Deleted) now
  publish []; VS Code client watches **/*.{pas,dpr,dpk,inc}; guard run_lsp_clear_diags_guard RED on 1.36.0,
  GREEN 4/4; all 44 run_lsp_*.ps1 guards #Requires -Version 7. ENGINE merges right AFTER 1.37.0, then lint-all.
- LSP-BACKLOG.md (gitignored, local): every delivered item closed; C17 (switch) closed; C18 (unowned) delivered.
- Tracker for ALL teams: docs\handoffs\UNMERGED-BRANCHES.md (UNCOMMITTED; linked from RESUME.md standing lists).
- IDE-test doc: LSP section written to C:\TEMP\claude\lanes\gaps\ide-test\lsp.md; ENGINE compiles the
  combined document once 1.37.0-alpha is staged.
- Side job: Delphi 5 integration notes for the owner: C:\TEMP\claude\c--Projects-Delphi-RAG-lint-LSP\a103c998-f4d7-4702-83af-1fa77b2e2ea4\scratchpad\DL-Delphi5-Integration.html
  (owner may ask later for the Level-1 Delphi 5 OTA package).

## Resume point (first actions)
1. `git log --oneline main | Select-String unowned` -- confirm ENGINE merged ca91e559; if not, ask ENGINE.
2. When ENGINE says 1.37.0-alpha is staged: check the combined IDE-test doc contains the LSP section and
   that `drag-lint-switch --help` in the install lists `--params` (lsp.md step 2 depends on it).
3. After merge on the main tree: lint-all on DRagLint.LSP.Server.pas scope (lane could not; no DB covers worktrees).

## Not done yet (owner-bound)
- Owner ruling: hover/definition for unowned files still answer from the main stores (cross-unit target may
  open the MAIN tree copy). Scope them, or keep with the label?
- LSP-BACKLOG A2, C6, D2 (no Rust toolchain), D3, section E, G0 parity -- need the owner in RAD Studio/VS Code.
- Owner deletes merged branches (agents' branch -d is refused): see UNMERGED-BRANCHES.md section 3 and 5,
  plus fix/lsp-*, fix/help-*, worktrees .claude\worktrees\lsp-switchrel, lsp-unowned, help-outroot.
- INBOX filed: docs\INBOX-index-gap-lsp-switch-not-in-manifest.md (switch .dproj in no manifest section).

## Gotchas
- RESUME.md carries another team's uncommitted edit -- commit only with care / leave to its owner.
- Agent isolation:"worktree" was refused once (core.worktree redirect); create worktrees by hand with
  `git worktree add .claude/worktrees/<n> -b <branch> main`.
- LSP guards that fail identically on main: proxy_byte_identity, proxy_merge_definition, switch*,
  (switch ones should clear with the rebuilt switch); proxy_lifecycle flaky under load; dlok_filtering and
  proxy_stub_modes timed out in the lane sweep (unproven).
