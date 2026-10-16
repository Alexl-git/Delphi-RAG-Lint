# HANDOFF 2026-10-16 -- ENGINE -- 1.31.4 type-name-prefix ancestry (1.31.3 is DONE)

Autonomous mode is armed (`~/.claude/autonomy/mode.json`, runId 20261016-1640). Read its `goal` and
`assumptions` first. The owner is away until Sunday 2026-10-18 and publishes 1.31.4 then.

## Status: 1.31.3 is complete
- origin/main has 1a5e40eb. Tag v1.31.3-alpha points at 1a5e40eb. The GitHub pre-release has both zips:
  https://github.com/Alexl-git/Delphi-RAG-Lint/releases/tag/v1.31.3-alpha
- Release battery: 693 pass / 0 fail. Wiki published. dll-win64 runs the Debug 1.31.3-alpha engine.
- UPDATE 2026-10-16 evening (owner present): everything pushed -- origin/main = 6f5508b1 (adds the
  remote-stop docs: CLAUDE.md "Building", docs\wiki\ide-release.md; pack-lint-release.ps1 now stages
  via stage-engine.ps1). Wiki republished; 1.31.3 release notes corrected. Autonomous mode was
  DISARMED (mode.json `mode: interactive`) -- re-arm it (autonomous skill) only if the owner leaves.
- `docs\NOTICE-2026-10-16-v1.31.3-released.md` is written. Like the other NOTICEs, it is untracked.

## Resume point (in order)
1. Re-arm the loop: `/loop` with an hourly ScheduleWakeup (~3600 s), so work resumes after the
   usage limit resets. Stop the loop when step 5 is done.
2. Execute `docs\superpowers\plans\2026-10-16-type-name-prefix-ancestry.md` (gitignored, in the main
   tree only) with superpowers:subagent-driven-development. Use sonnet implementers for Tasks 1-4
   and haiku for Task 5. Decisions D1-D4 are DECIDED in its section 2.
   **Read every "1.31.3" in the plan's Task 5 and section 6 as 1.31.4-alpha** (D3).
   No extractor bump, so no reindex.
3. Battery green (`tests\run_battery.ps1`, logged to a file, about 2 h today) -> commit with a pathspec.
4. Deploy the Debug 1.31.4 engine to dll-win64 (owner: yes, if `ListAgents` shows no other session
   mid-gate). The exe is often locked by short-lived engines, so FIRST run
   `drag-lint ide-release --seconds 900` and `drag-lint shutdown --all --wait 30`, then build or
   stage (`build\build_draglint_win64.bat`; `build\stage-engine.ps1` kills a holder and retries).
   Then `build\pack-lint-release.ps1 -Version 1.31.4-alpha`. If only the dll-win64 copy fails after
   both Release builds succeed, `-SkipBuild` zips those fresh binaries (check their mtimes first).
   Write `docs\NOTICE-<date>-v1.31.4-ready.md`.
5. **Do NOT push, tag or release 1.31.4.** Put the exact commands for the owner into a new handoff:
   `git push origin main`; `git tag -a v1.31.4-alpha <sha> -m v1.31.4-alpha`;
   `git push origin v1.31.4-alpha`; `gh release create v1.31.4-alpha --verify-tag --prerelease`
   with the two zips and a notes file.
   Then set mode.json `phase: complete` and stop the loop.

## Gotchas
- An existing local tag makes `git tag <t>` fail, and the push then sends the OLD tag. Verify with
  `git ls-remote origin 'refs/tags/<t>^{}'`.
- `gh release create --target` needs a full SHA. Push the tag and use `--verify-tag`.
- Never run pack or a build beside a running battery: pack swaps dll-win64\drag-lint.exe.
- Another writer edited `tests\autotest\run_lint_stage1_store_parity.ps1` and `docs\INBOX-INDEX.md`
  at about 15:00 on 2026-10-16. Re-read any file before editing it.
- The v1.31.3 release notes still say "zips are attached after the battery". Fixing that text needs
  `gh release edit`, which is guarded, so it is left for the owner.
