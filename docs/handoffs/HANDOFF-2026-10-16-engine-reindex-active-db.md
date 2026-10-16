# HANDOFF 2026-10-16 -- engine -- reindex targets the active project's DB (1.31.2-alpha)

## Status

* DEFECT (owner report): stale `duplicate-global-decl` on deleted line 80 of
  `C:\Projects\DB\ORM3\COMMON\BASICS.PAS` survived save + Rescan + refresh.
* ROOT CAUSE: plugin global `GLastProjectDb` = the LAST .dproj OPENED, paired with the ACTIVE
  project in `QueueReindexJob`. IDE opened Micronite2027 then Delphi13MigrationAssistant (03:56),
  so every save/Rescan ran `index --project Micronite2027.dproj --db ...\Delphi13MigrationAssistant.sqlite`.
  Micronite2027.sqlite never refreshed; the migration DB was overwritten (project_tag=Micronite2027, 632 files).
  Hidden because JobQueue.RunOne logged no cmdline/exit.
* FIXED, merged to local main 50e5c5e2 (branch fix/reindex-active-project-db: bb637cec engine,
  15ad51cd + c3493c9e plugin). `GLastProjectDb` removed; new `DbResolver.ActiveProjectWriteDb` /
  `IndexJob.ReindexTargetDb` (manifest unique owner or refuse). JobQueue logs cmdline + exit.
  ProjectNotifier open-time index now `index --project` (was forbidden `index <dir> --db`; `--scan-libraries` dropped).
  Engine: `index --project X --db Y` exits 2 when Y.project_tag names another project; `--rebuild` proceeds with a NOTE.
* DEPLOYED (owner go, IDE closed, 11:37): dll-win64 drag-lint.exe 1.31.2-alpha; Win32+Win64 BPLs, committed 11d0ff67.
* REPAIRED: Micronite2027.sqlite reindexed (BASICS fresh); Delphi13MigrationAssistant.sqlite `--rebuild` -> own tag, 7 files.
  Live refusal verified (exit 2) before the rebuild.
* NOT PUSHED: main is 9 ahead of origin (includes converter's b06913fc / 7994566e / fb0f6803 / c5fe2324).

## Resume point

1. Owner tests in IDE: edit/save BASICS.PAS or Rescan; plugin log
   (`%LOCALAPPDATA%\drag-lint\logs\drag-lint-plugin.log` / telemetry log) must show the job cmdline with
   `--db ...\Micronite2027.sqlite`; marker clears after ~20 s.
2. If good: push main (owner consent), then the planned reindex (after 17:00 per owner).
3. Toxicity Metrics: AWAITING owner yes/no. Proposal: write HKCU\Software\Embarcadero\BDS\37.0\Code Metrics
   `ParamCountThreshold`=7, `IfDepthThreshold`=5, `CyclomaticComplexityThreshold`=30; leave
   `FunctionLengthThreshold`=20 (IDE counts statements, drag-lint counts lines). Write ONLY with RAD Studio
   closed (read once at startup; options page may overwrite).
4. Tell charts-27 about 1.31.2 deploy + converter's rules restructure (my SendMessage to charts was
   blocked by the permission classifier). Owner asked whether a PS->Delphi chart conversion fits before 17:00 -- charts-27 owns that.

## Not done yet (incidental, from implementer)

* ProjectNotifier still picks its DB via `ManifestDbForFile` (folder fallback can name another project's DB;
  engine refusal only catches TAGGED DBs).
* Plugin "scan libraries" setting is now inert -- remove or rewire.
* 12 autotests ignore `-Exe` and hardcode the deployed exe path.
* `pending_stale_library_store_degrades` autotest fails on old engine too (pre-existing).
* Offer check in StructureForm reads the manifest per call (low severity perf).
* Workspace mode: saves now reindex the manifest owner, not the workspace shared DB (deliberate).

## Gotchas

* Worktree `.claude\worktrees\agent-a11afcc4b2c8afb92` (branch worktree-agent-a11afcc4b2c8afb92) still exists; remove after push.
* stash@{0} is the owner's (P3 Wizard reformat) -- keep.
* Dirty tree files (dclDragLintWizard.dproj/.delphilsp.json, drag-lint.json x2, CLAUDE.md) are not this stream's.
