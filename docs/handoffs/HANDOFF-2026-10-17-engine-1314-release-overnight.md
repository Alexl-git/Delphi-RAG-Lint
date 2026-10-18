# HANDOFF 2026-10-17 -- ENGINE -- 1.31.4 release run in flight + owner's overnight asks

Supersedes HANDOFF-2026-10-16-engine-1314-type-prefix-ancestry.md (its steps 0-2 are DONE).
Autonomous: global `~/.claude/autonomy/mode.json` is CHARTS' file (runId 20261016-1755); ENGINE only
added an assumption line. ENGINE never sets its `phase`. Owner away overnight 2026-10-17 -> late morning
or early afternoon 2026-10-18.

## Status
- 1.31.4-alpha CODE DONE on main, reviewed (SDD: 5 tasks + final whole-branch review + 1 fix wave):
  66cb006e..36dc1866 (d5c20ad3, 608bd4b3, cb6780f0, 0b626cfa, 44a978b9, d9efd1d5, 36dc1866). NOT pushed.
- Ledger with every ruling (R1-R11) and deferred minors:
  `.superpowers\sdd\2026-10-16-type-name-prefix-ancestry\progress.md` (gitignored). Rulings the owner
  should read: R2 (how D1 was read: untraceable ancestor with a library index = ERROR index-gap finding;
  no library / no --db = silent except missing ancestor/TObject -> T, Exception -> E; stale class absent
  from the project index = silent), R8 (fixture), R9 (deploy BEFORE battery), R10 (backlog-index guard
  red = pre-existing INBOX-INDEX count drift, left alone).
- Changed-line lint: lint 0 on all 4 units; lint-all 1 pre-existing duplicate-code (NamingChecks.pas:653).
- RELEASE RUN IN FLIGHT (sonnet subagent, dispatched 20:46 2026-10-17), steps:
  0 generic-name check (Box<T> must still fire T; STOP if silent) -> 1 back up dll-win64 exe as
  `drag-lint.exe.bak-1.31.3-20261017` -> 2 wait until 21:15 (CHARTS was asked go/hold) -> 3
  `ide-release` + `build\build_draglint_win64.bat` (deploys Debug 1.31.4) -> 4 full battery (~2 h) ->
  5 `build\pack-lint-release.ps1 -Version 1.31.4-alpha` -> 6 `docs\NOTICE-2026-10-17-v1.31.4-ready.md`.
  Its report: `.superpowers\sdd\2026-10-16-type-name-prefix-ancestry\release-report.md`;
  logs: `C:\TEMP\claude\sdd-1314\release\` (battery.log).
- Two read-only analysts in flight (owner asks), findings land in:
  `.superpowers\sdd\library-rescan-check.md` and `.superpowers\sdd\user-side-powershell.md`.
- CHARTS (session charts-61) asked for the last-chart ETA, branch/tip, whether it needs an engine
  merge, and any remaining user-side PowerShell. Answer arrives as a cross-session message (may be lost
  across /clear -- re-ask if none in the transcript).

## Release run state at ~21:45 (agent handed back mid-run; NO release-report.md written)
- STEP 0 PASS: Box<T> fires T, EBox<T> silent, controls fire; index stores `Box<T>`.
- STEP 1: backup `third_party\dll-win64\drag-lint.exe.bak-1.31.3-20261017`, sha256 1F2F92BB...0CBF.
- STEP 3 DONE: dll-win64 = Debug 1.31.4-alpha, sha256 584450377055F913AEC0EBE49DCADDEBF00679FEC1621E695F688154B1F00F1C.
- STEP 4 RUNNING: battery started 21:15:58, `C:\TEMP\claude\sdd-1314\release\battery.log` (+ battery.err).
  Three pre-existing drag-lint.exe (PIDs 135936, 165708, 172520) were alive -- possible timeout source.
- TODO: wait for the battery to end (check `Get-Process pwsh` + log mtime); read the count line; re-run each
  failure alone (backlog-index guard is known red, R10); then STEP 5 `build\pack-lint-release.ps1
  -Version 1.31.4-alpha` and STEP 6 NOTICE (see Status for its contents). Then the library rescan.

## Resume point (in order)
1. Re-arm the hourly wake timer (`/loop` dynamic, ScheduleWakeup ~3600 s) -- owner is away overnight.
2. Release run: read release-report.md. If missing, check `Get-Process pwsh,drag-lint`, the tail of
   `C:\TEMP\claude\sdd-1314\release\battery.log`, and `third_party\dll-win64\drag-lint.exe --version`;
   finish whichever step is open (never pack beside a running battery). STEP 0 BLOCKED = generic class
   regression in ClassifyClassOrigin (`LibraryKnowsType(AStore, ATypeName)` ~NamingChecks.pas:246) ->
   fix (sonnet implementer, add a Box<T> case to the runner), rebuild, then resume the run.
3. Library rescan -- VERDICT (analyst, 21:00): YES, both DBs (Win64 4305/7001 changed, Win32 4632/7105,
   resolver 1.11.0 vs engine 1.12.0; DevExpress folder 2026-10-13 newer than both DBs). Roots are
   re-read from the IDE registry on every run (drag-lint.json:297-318 `registry-libraries`), so no root
   edit is needed; `library-drift` (manual verb, not auto-run) lists 7 roots with no indexed files
   (BonusKSVC 8.0.3, Raize DM2/IX2 Win64, DevExpress RS37 Win64). Command, AFTER the battery:
   `drag-lint.exe index --all --only Library` (try `--dry-run` first), then `library-drift --json`
   (expect 0). Duration undocumented -- log it. Owner: "now is a good time" (away overnight).
   Details: read library-rescan-check.md. If a rescan is needed
   (2026-10-16 note: library-Win64 reported 4305/7001 files changed + resolver version behind), run it
   AFTER the battery finishes and BEFORE any other build; if IDE Library/Browsing paths changed
   (Delphi + DevExpress upgrade), update the library roots first. Report whether roots are checked
   automatically before each scan; if not, that is a backlog item (INBOX note).
4. User-side PowerShell: read user-side-powershell.md; answer the owner (anything besides charts?).
5. If CHARTS' ETA leaves time (> ~3 h) and the battery is done: fix ONE known bug from
   `docs\superpowers\plans\2026-10-14-open-defects-triage.md` (batches 2-5) in a worktree, full SDD,
   commit only. Do not deploy it.
6. When CHARTS lands the last chart: build a TEST installer for another computer (engine release zip +
   plugin; see pack-lint-release.ps1 and the installer R2 notes, memory
   project_installer_r2_engine_duties.md). Deploy of BPL needs RAD Studio closed + owner "go".
6b. CHARTS reply (2026-10-17 ~21:40): "go" for the 1.31.4 deploy. Round-trip ETA 01:00-03:00 Sunday
   (Tasks 3-9 + final review left). Merge to main IN ORDER, all fast-forward (worktree archify-ir):
   cb-compare-pairing @1f8f10f6 -> b1-who-calls @3e3c08cf -> b2-butterfly-hierarchy @23d60c68 ->
   b3-wiring-path @c8e5defc -> b4-architecture-cycles @f6807f0b -> b5-member-access @49d6b789 ->
   charts/d1-round-trip (tip when done). For the test installer, ENGINE must ALSO: (a) wire
   build\build_uri_handler.bat into build_draglint_win64.bat / publish-release (Build-Installer throws
   without drag-lint-open.exe); (b) regenerate doc-drift 'Used by' facts with `document --unit --apply`
   on Core.Interfaces, Core.Model (~:891), Report.Deps, Query.Callers (:27/:99). After d1, no chart
   uses PowerShell; the installer's own pwsh steps (protocol registration, MCP config, pwsh detection
   page -- see .superpowers\sdd\user-side-powershell.md) remain to be replaced. CHARTS status doc:
   C:\Projects\Delphi-RAG-lint-wt\archify-ir\docs\superpowers\RESUME-charts-2026-10-17.md.
7. Owner handoff for publishing 1.31.4 (owner runs these, Sunday): `git push origin main`;
   `git tag -a v1.31.4-alpha 36dc1866 -m v1.31.4-alpha` (or the final HEAD); `git push origin v1.31.4-alpha`;
   `gh release create v1.31.4-alpha --verify-tag --prerelease <win64.zip> <win32.zip> --notes-file <notes>`.
   Verify first: `git ls-remote origin 'refs/tags/v1.31.4-alpha^{}'`.
7b. DONE 2026-10-17 ~21:30: hooks\draglint-first.js + test (8/8) wired in settings.json (backup
   settings.json.bak-20261017-nogrep); global CLAUDE.md prose replaced by one line; nogrep SKILL.md
   note added. Known gaps (optional follow-up): Grep over a folder with no glob/type is not caught;
   a shell pattern ending in Foo.pas can false-deny. ORIGINAL ask, for reference: Build
   `~/.claude/hooks/draglint-first.js` (PreToolUse on Grep|Glob|Read + Bash|PowerShell grep/rg/Select-String)
   + a PostToolUse recorder of drag-lint.exe calls (state file per session). Deny Grep/search on
   .pas/.dfm/.dpr/.dpk under a folder with `_D-RAG\*.sqlite` unless a drag-lint query ran in this session
   in the last ~5 min (deny reason names the right verb); deny whole-file Read of .pas/.dfm > ~2000 lines
   without offset/limit (reason: `outline --file` first); auto-log allowed fallbacks to
   `stats\draglint-gaps.log`. Applies to subagents too. Deny, never "ask" (autonomous mode). Test with a
   small node test; use the update-config skill to wire settings.json. Then propose trimming the CLAUDE.md
   drag-lint block. No Delphi build needed -- can run beside the battery.
7c. Owner ask (2026-10-17 ~22:00): the PRODUCT's AI instructions (docs\AI-USAGE.md, README AI section,
   docs\wiki AI pages) do not reflect reality and only MENTION drag-lint. Update them to tell users to
   INSTALL the enforcement hooks. Steps:
   - Wait until the hook agent finishes extension 2 (Agent-dispatch + manual-tracing nudges, stats).
   - Ship the hook as a product file, e.g. `integrations\claude-code\draglint-first.js` + test + a settings
     snippet. Make it generic: no C:\Projects paths; exe and stats paths from env/config, defaulting to
     the installed layout (memory project_installed_layout_v2.md).
   - Add an install step: an install verb or a documented copy step. The installer may offer it; that
     is the CHARTS/installer seam, so coordinate.
   - Rewrite AI-USAGE so it matches the real verb surface (docs-sync guard), with a "question shape ->
     verb" table and "install the hook" as step 1.
   - Feature-registry entry (-Surface for the integration file), build-feature-pages -Normalise, then
     run the docs-sync and registry guards.
   SDD with a written plan first (spec-loop): this is a product feature, not a doc tweak.
8. Late morning 2026-10-18: billing split help -- memory `project_billing_split_orm3_dl.md`.

## Gotchas
- The autonomy guard blocks ANY shell command whose text contains drag-lint's engine stand-down verb
  (it reads it as OS shutdown) -- even inside a heredoc or log text. Use Edit for ledger text; let
  `stage-engine.ps1` deal with exe holders.
- The test runner `run_type_prefix_exception_ancestor.ps1` defaults `-Exe` to dll-win64; before the
  deploy it tests 1.31.3 and FAILS (expected).
- Controller context ran to 86% of the 250k budget -- delegate bulky work.
