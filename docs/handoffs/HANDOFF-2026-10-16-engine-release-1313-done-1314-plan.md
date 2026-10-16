# HANDOFF 2026-10-16 -- ENGINE -- 1.31.3 published (zips pending), then 1.31.4 type-prefix ancestry

Supersedes `HANDOFF-2026-10-16-engine-release-1313-type-prefix-ancestry.md` (now `resumed`).
Owner away from ~17:30 2026-10-16 until Sunday 2026-10-18. Autonomous mode ARMED
(`~/.claude/autonomy/mode.json`, runId 20261016-1640) -- read its `goal` and `assumptions`.

## Status
- `1a5e40eb` pushed to origin/main: stale-index naming autofix is all-or-nothing when the new name
  differs beyond case (`NamingFix.BuildNamingFixEdits`); battery re-pins (store parity A4 + new A5
  control, rule-catalog naming 10 -> 11). CHANGELOG v1.31.3 has the line.
- Tag `v1.31.3-alpha` -> `1a5e40eb` pushed (moved from cd9fa7ee with the owner present).
  GitHub pre-release EXISTS with NO assets: https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v1.31.3-alpha
- Wiki published 2026-10-16 ~16:40 (`tools\publish-wiki.ps1`, exit 0).
- `tools\publish-release.ps1 -Version 1.31.3-alpha -BuildPlugin` running in the background;
  log `C:\TEMP\claude\release-1.31.3\real2.log`. Steps 0-3 passed; step 4 battery was at 380/693
  with 0 fails at 16:40. Steps 5 (wiki, idempotent) and 6 (pack: Release Win64+Win32 zips to
  `C:\TEMP\rel-1.31.3-alpha\`, deploys the Release Win64 exe to dll-win64... then restores the
  Debug one) follow.
- Uncommitted from that run: `third_party\dll-win32\dclDragLintWizard.bpl/.dcp` (rebuilt by
  -BuildPlugin, IDE closed). Not ours: both `drag-lint.json`.

## Resume point (in order)
1. Read the tail of `real2.log`. Battery green -> continue. A FAIL -> fix it, commit, re-run only
   that runner; then `build\pack-lint-release.ps1 -Version 1.31.3-alpha` if step 6 did not run.
2. `gh release upload v1.31.3-alpha C:\TEMP\rel-1.31.3-alpha\drag-lint-v1.31.3-alpha-win64.zip C:\TEMP\rel-1.31.3-alpha\drag-lint-v1.31.3-alpha-win32.zip`
   (not on the autonomy guard list). Commit the plugin BPL/DCP with a pathspec. Write
   `docs\NOTICE-2026-10-16-v1.31.3-released.md` (to CONVERTER, CHARTS: release URL, 1a5e40eb,
   battery count, dll-win64 sha256, extractor unchanged -- no reindex).
3. Execute `docs\superpowers\plans\2026-10-16-type-name-prefix-ancestry.md` (gitignored, main tree)
   with superpowers:subagent-driven-development (sonnet implementers Tasks 1-4, haiku Task 5).
   Decisions D1-D4 are DECIDED in its section 2. The plan text still says "1.31.3" in Task 5 and
   section 6 -- read every version string as **1.31.4-alpha** (D3).
4. Battery green -> commit -> deploy the 1.31.4 Debug engine to dll-win64 if `ListAgents` shows no
   other session mid-gate (owner yes) -> `build\pack-lint-release.ps1 -Version 1.31.4-alpha`.
5. **Do NOT push, tag or release 1.31.4** -- the owner does it Sunday (owner ruling). Write the
   exact commands into a new handoff, set mode.json `phase: complete`, stop the /loop.
6. Loop: hourly `ScheduleWakeup` (~3600 s) so work resumes after usage limits reset.

## Gotchas
- An old annotated `v1.31.3-alpha` tag existed locally at cd9fa7ee; `git tag` without `-f` fails
  silently into pushing the old one. Check `git ls-remote origin 'refs/tags/<t>^{}'` after a tag push.
- `gh release create --target` needs a full SHA; push the tag first and use `--verify-tag`.
- pack replaces dll-win64\drag-lint.exe during the run -- never run it beside a battery.
- Battery is slow today (~5 runners/min, 100% CPU from its own pwsh workers); WerFault pid 174200
  has been alive since 13:56 but idle.
- Another writer edited `tests\autotest\run_lint_stage1_store_parity.ps1` concurrently at ~15:00
  and recounted `docs\INBOX-INDEX.md` at 15:07 (no live engine peer in ListAgents). Re-read before editing.
- No reindex needed: `DRAGLINT_EXTRACTOR_VERSION` unchanged in 1.31.3 and in the plan.
