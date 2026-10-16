# HANDOFF 2026-10-16 -- ENGINE -- release 1.31.3-alpha, then type-name-prefix ancestry (1.31.4)

## Status
- `cd9fa7ee` on local `main`: "release: v1.31.3-alpha". It contains:
  - (A) Fix all owner freshness: a `.dproj` member under a registry library root
    (ArrayHelper.pas) no longer counts as missing, so the multi-project rename apply stops
    dropping every rename. `ProjectOwnedMembers` in `src\refactor\DRagLint.Refactor.MultiProjectRename.pas`.
    The CLI summary now says `nothing written -- N rename(s) dropped: <reason>`.
  - (B) Plugin wait cursor while a Fix it / Fix all job runs, and a second fix is refused
    meanwhile (`Busy` jobs in `DragLint.Plugin.JobQueue.pas`, hook + `RefusedWhileFixRuns` in
    `DragLint.Plugin.StructureForm.pas`).
  - (C) type-name-prefix name heuristic `AncestorNamedLikeException`
    (`EKeyViolation = class(EDatabaseError)` is no longer told to use T).
  - It also carries the registry entry `fix-all-reliability`, its wiki page, the NOTICE and the 4 plugin BPL/DCP files.
- Engine and BPLs were deployed at 12:32 (dll-win64 / dll-win32), built from the source before
  the version bump, so the exe still says 1.31.2.
- **NOT pushed, tagged or released.** main is 10 commits ahead of origin, including 1.31.2 and the
  converter's b06913fc. The owner approved push + tag + GitHub pre-release on 2026-10-16.
- The owner has not yet re-tested Fix all on ORM3 BASICS.PAS in the IDE. It will now write 74
  renames across 4 projects.

## Resume point (in order)
1. Fix the 9 battery failures (log `C:\TEMP\claude\release-1.31.3\real.log`; read selectively):
   - `run_mcp_protocol_guard`, `run_smoke`, `run_exe_freshness`: exe not rebuilt (the release
     ran with `-SkipBuild`). A rebuild clears them.
   - `run_encoding_guard`: 1 file with a lone LF, probably one the release agent wrote
     (wiki page / NOTICE / CHANGELOG). Find it and normalise it.
   - `run_rulecatalog_tests`: naming count = 10 (2 fail). Check whether (C) changed what the catalogue counts.
   - `run_lint_stage1_store_parity` A4: store-free lint of `EFoo = class(Exception)` no longer
     reports. That is the INTENDED effect of (C), but update the test deliberately: re-read what A4
     pins and keep a positive control. Never weaken it.
   - `run_fix_stale_index_guard`: "glyActive still present at both sites". Uninvestigated.
   - `run_backlog_index_guard`: the INBOX headline says 24, but 39 notes are on disk. Recount `docs\INBOX-INDEX.md`.
   - `run_feature_registry_harvest`: uninvestigated.
2. `tools\publish-release.ps1 -Version 1.31.3-alpha` WITHOUT `-SkipBuild` (`-DryRun` first). Battery green.
3. Approved by the owner: `git push`, tag `v1.31.3-alpha`, `gh release create --prerelease`.
4. Execute the plan `docs\superpowers\plans\2026-10-16-type-name-prefix-ancestry.md`
   (gitignored, main tree only) with superpowers:subagent-driven-development: sonnet
   implementers, haiku for docs. Owner decisions:
   - D1: a parent that is named but found in neither the project nor the library index ->
     ERROR-severity index-gap finding and no prefix finding. No index at all -> silent.
   - D2: one shared classification helper (rule and fixer).
   - D3: ships as 1.31.4-alpha.
   - D4: registry entry yes.
   Then commit, push, release 1.31.4-alpha.
5. **Owner instruction:** after resuming, run as `/loop` with an hourly ScheduleWakeup
   (~3600 s), so work continues after usage limits reset, until 1.31.4 is released. Stop the loop then.

## Gotchas
- No reindex is needed: `DRAGLINT_EXTRACTOR_VERSION` is unchanged in both 1.31.3 and the plan. The pending
  all-teams 1.22 extractor re-parse is separate (held for CHARTS); never run it during a build.
- A `drag-lint.exe` from `src\cli\Win64\Debug` has no `drag-lint.json` beside it, so
  multi-project owner discovery sees NO manifest (`rename-local:` only). For a real preview use
  `dll-win64` or a scratch copy with the manifest.
- Uncommitted and not ours: `third_party\dll-win32|win64\drag-lint.json`, plus many `??` files from other teams.
- Plugin BPL deploy needs RAD Studio closed. VS Code's `drag-lint lsp` processes run a private
  engine copy and do not lock dll-win64.
