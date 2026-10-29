# HANDOFF 2026-10-29 ENGINE -- 1.38 prep done; owner IDE test; next = plan A (auto uses on save)

Resumes/closes: HANDOFF-2026-10-29-engine-rel138x-deploy-pending.md (all its steps done; detail in its "DONE 14:37" section).

## Status (16:30)
- main = 1.38.0-alpha release prep, LOCAL, 536 commits ahead of origin (push was BLOCKED: session ran in autonomous mode).
  Merges today: ab8e60dc rel/138x; 896fb465 concat-in-loop per-routine scope; 54e2a09c VS Code watch-on-disk + Refresh Problems;
  5d3e0980 LSP verified vscode-extension; 15897488 purity-stage speed (1-file incremental index 61 s -> 27 s); 1a1338da manifest regen.
- Deployed: dll-win64\drag-lint.exe from main 15897488 (14:36, hash ok); plugin BPL/DCP = RC (unchanged since). VS Code ext 1.6.1
  packaged (dist\drag-lint-1.6.1.vsix) and installed into Code-dl + Code-gmail -> owner reloads windows.
- Battery on main 56/62 (6 known pre-existing fails: purity_stage case 28; lsp full_rules, inlay_hint, switch, switch_params, switch_vscode).
  lint-all: 0 real findings on changed lines.
- Owner rulings: skip 1.37.0; all work targets 1.38; publish after owner's IDE test; CONVERTER re-pin to 1.38 (told, held for budget);
  "fixable" = 111 stays; calls-stage speed = early next week.
- WWW 1.38 drafts ready (www-9b told): missing-uses article verified vs deployed exe; new WWW\articles\2026-10-30-what-the-index-saved-you;
  site facts 290/18/111. Publish on owner go only.
- Cleanup done: old exes + 1.28-1.31 .bak deleted; 141 merged/clean/idle worktrees removed (44 left: 18 unmerged, 22 with
  uncommitted/untracked files, 3 locked -- list via `git worktree list`; dirty list in session scratch only).

## OWNER: run these (blocked in autonomous mode)
```
cd C:\Projects\Delphi-RAG-lint
git push origin main
git branch -D verify/1351-cycc worktree-agent-a894c17432443ce85 worktree-agent-ab5fcea23bf1d0159 worktree-agent-a97a7239db384f5fa worktree-agent-a08b3329d53564793 worktree-agent-a5dd69f27b7607079 worktree-agent-a6b5582308fdac22f worktree-agent-a7205be6bd212ec86 worktree-agent-acc26006502f247af worktree-agent-ab395cfc4fa18f85e worktree-agent-a3b9d0e9925b84522 worktree-agent-ad1b2e68c0f021432
git stash drop stash@{0}    # agent:merge-rel138x stale leaks (baseline 1.26 PLACEHOLDER + 3 old Clippy test copies); stash@{1} = owner P3, keep
```
(The 12 branches: analyst triage -- already in main by patch-id or superseded by 8ccbd06f / 3b434b08 / b68d9a77. Remove their worktrees first if git refuses.)

## Resume point (in order)
1. Ask owner: IDE test result of 1.38 (go/no-go to publish). On go: tag + gh release + WWW publish (www-9b) -- each needs owner go.
2. Implement PLAN A: `docs\superpowers\plans\2026-10-29-auto-uses-on-save.md` (gitignored folder -- local file; 6 tasks, 3 HPS lanes
   LSP / rule / docs; models stated per task). Open owner decisions in the plan: A-D6 drop-on-save default off?; A-D2 freshness gate
   strictness (whole index fresh vs current-file hash). Offer superpowers:subagent-driven-development.
3. Rebase lanes for the 2 branches with work not in main: feat/index-fill-prop-types 54ca1379 (M; 6 conflicts incl. CLI.pas,
   Convert.PropTree.pas; decide extractor bump -- it changes what index writes) and worktree-agent-ae49d9f476c2d9426 909fc131
   (help --out/--json; S-M; redo on main or drop with reason; main baseline cells = 108).
4. Early next week: PLAN B `docs\superpowers\plans\2026-10-29-calls-stage-incremental-cost.md` (decisions B-1 acceptance number, B-2 --hash-always).

## Not done / backlog
- gaps/ext-dirword PARKED (grammar, needs extractor bump + re-parse; 1-3 weeks).
- C:\Projects\DB\ORM3\drag-lint.sqlite is 192 MB and was WRITTEN 09:05 today -> not the "2 GB junk"; find its writer before deleting.
- resolve-dbs: no manifest section for src\cli\drag-lint.dproj; src\cli\_D-RAG\drag-lint.sqlite stale (57/231) -- reindex / add manifest row.
- Plugin INFINITE waits JobQueue.pas:664, LspWriteQueue.pas:298 (low). vscode-extension entry: optional gaps no-questions/no-access (LSP, next wave).
- Full backlog snapshot (analyst, 2026-10-29): items E1-E24, C1-C15, L1-L11, W1-W6 -- regenerate on demand; not stored.

## Gotchas
- src\cli\Win64\Debug\rules can be STALE (113 vs 197 files) -> docs_sync + registry guards fail falsely. robocopy rules /MIR before guards.
- Plugin index src\delphi-plugin\_D-RAG\dclDragLintWizard.sqlite must be fresh or the registry guard fails "menu-tree exited 3".
- A reused lint DB copy indexed from another worktree path doubles files -> duplicate-code hits vs the other path (artefact).
- docs\superpowers\plans is gitignored. Push/branch -D/stash drop are refused in autonomous mode.
