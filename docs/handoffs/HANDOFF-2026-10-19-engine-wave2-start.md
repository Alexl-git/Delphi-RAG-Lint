# HANDOFF 2026-10-19 -- ENGINE -- 1.31.5 RELEASED; next: wave 2 (bugs + TODOs)

Supersedes HANDOFF-2026-10-18-engine-1315-owner-gates.md (closed).

## Status
- v1.31.5-alpha PUBLISHED: https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v1.31.5-alpha
  (pre-release, asset = installer only). Tag on f10795d4 = origin/main (pushed 2026-10-19).
- Owner SKIPPED the VM test of the 1.31.5 installer (owner instruction 2026-10-19).
- Deployed: dll-win64 engine 1.31.5 (sha 201DE760) + drag-lint-config.exe (.bak-1.31.4 copies beside
  them); BPLs Win32+Win64 1.31.5 (693ae603). VS Code extension still runs its own engine copy until
  "drag-lint: Update Engine Copy Now".
- Cleanup done: all wave-1.31.5 lane worktrees + wave-1315 removed, their branches deleted, plus 4 old
  merged agent worktrees/branches. KEPT: `.claude\worktrees\agent-a1a2c9ef4e67b4f18` =
  `fix/extractor-dollar-ident-bare-call` (4 unmerged commits, the HELD 1.22 extractor release), and
  `C:\Projects\Delphi-RAG-lint-wt\*` (other streams).

## Resume point -- wave 2
1. Read the wave-2 list: `docs\superpowers\plans\2026-10-18-bugfix-wave-1.31.5.md` (gitignored; the
   "wave 2" / follow-ups section, ~1-1.5 days) and the costed backlog
   `docs\BACKLOG-2026-10-18-consolidated.md` (gitignored). Items not in a wave yet wait for owner
   prioritisation (T-01..T-23).
2. Lane follow-ups found in 1.31.5 (add to wave 2):
   - lint --fix --apply without --project-rules silently skips doc-drift fixes (lane 6);
   - 'declaration' appears as a Used-by caller name (lane 6);
   - YADFOT new DB reports 162/174 files outside closure (lane 6);
   - watch-mode FScopeWhole latch never reset between ticks (lane 2);
   - prune ids counted as 'changed' in the whole-DB reason (lane 2);
   - publish-release.ps1 still builds zips; installer build should replace it (B-01/T-19).
3. Battery hygiene seen this run: a fresh worktree fails 7 guards on untracked artifacts
   (tests\calls.sqlite, LspStubServer.exe, lsp-switch exe, src\cli\_D-RAG self-index, tests\fixtures
   T2-T7 exes from May 2026) -- worth a "battery prerequisites" step or self-building guards.
4. Write a wave-2 plan (lanes, like wave 1.31.5), dispatch, merge into an integration branch, build in
   its worktree, full battery, then release 1.31.6 the same way.

## Gotchas
- HELD: 1.22 extractor release (all teams, ~5 h re-parse); add
  src\analysis\DRagLint.Analysis.Flow.Lattices.pas to the extractor hash surface then (lane 8).
- CHANGELOG "Unreleased" block holds charts work already shipped in 1.31.4 -- owner decision pending.
- Lanes run as THIS session's subagents lock their worktrees with the session pid; unlock before
  removing.
- stash@{0} is the owner's -- keep.
