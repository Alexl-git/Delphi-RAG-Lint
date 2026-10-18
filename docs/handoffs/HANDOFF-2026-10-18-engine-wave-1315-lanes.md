# HANDOFF 2026-10-18 -- ENGINE -- bug-fix wave 1.31.5 in progress (parallel lanes)

Supersedes HANDOFF-2026-10-18-engine-1314-vm-retest.md (1.31.4 is PUBLISHED).

## Status
- v1.31.4-alpha published 2026-10-18: tag on 779d8ccc, asset = installer only
  (installer\Output\drag-lint-setup-1.31.4-alpha.exe). Owner decision: the INSTALLER is the release
  package from now on; zips no longer published.
- main is 1 commit ahead of origin (454982b1, .gitignore for .bak-*). Not pushed.
- Wave plan + all follow-ups found by lanes: `docs\superpowers\plans\2026-10-18-bugfix-wave-1.31.5.md`
  (gitignored, local). Full backlog with costs: `docs\BACKLOG-2026-10-18-consolidated.md` (gitignored).
- Integration branch `wave/1315`, worktree `C:\Projects\Delphi-RAG-lint\.claude\worktrees\wave-1315`
  (main + 18 commits). Built nowhere yet. MERGED lanes:
  - 1 fix/1315-vm-polish: binary DFM diagnostic (raw-byte check in Core.Indexer, EnsureUtf8Bytes
    UNCHANGED), FTS5 AVAILABLE line removed from stderr. Guard run_vm_polish_guard.ps1.
  - 3 fix/1315-unit-aliases: 490 unscoped RTL/VCL names (walked from Studio 37 source), neutral
    advice text. Guard run_used_unit_rtl_aliases.ps1.
  - 4 fix/1315-config-save: Config Save edit-only into loaded file (B-22), resolve-dbs --in NOTE
    (B-20), migrate-dbs keeps unmodelled keys via TManifestIO.SaveEdits. Guards run_config_save_guard,
    run_resolve_dbs_in_uncovered, run_migrate_dbs_keeps_unmodelled_keys.
  - 5 fix/1315-rename-closure: owner checked against compile closure (B-03); B-04 verified fixed.
  - 8 fix/1315-lint-fps: B-08 TArray<T>.Create not a leak; B-14 with-record not a read.
  - 9 fix/1315-plugin-timeout: ProcRun timeout enforced + job-object tree kill (B-19). BPL NOT deployed.
- Lane 10 (verify): B-04, B-09, B-15, B-16(pchar), B-32 all FIXED on 1.31.4 -> close those INBOX notes.

## Resume point
1. (DONE: all lanes merged into wave/1315 by the old session.) Lanes STILL RUNNING at handoff (background subagents of the old session; they commit to their
   branches even after /clear): 2 `fix/1315-fresh-db-notes` (V-C), 6 `fix/1315-doc-tools`
   (B-05/06/07), 7 `fix/1315-allow` (B-10/11/12). Check: `git log --oneline main..<branch>` and
   process/mtime activity in `.claude\worktrees\agent-*`. If a branch has no fix commit and its
   worktree is idle, re-dispatch that lane (prompt shape: see the plan's lane table).
2. Merge each into wave/1315 (`git -C .claude\worktrees\wave-1315 merge --no-ff <branch>`).
3. Re-baseline `tests\extractor-version.baseline` ONCE, with a written reason, NO version bump
   (binary-DFM raw-byte check in Core.Indexer: text-file extraction byte-identical; SaveEdits is a
   writer; lane 4 already re-pinned once -- re-pin over it). Run run_extractor_version_guard.ps1.
4. Bump DRAGLINT_VERSION -> 1.31.5-alpha; CHANGELOG from the lines below; build in the wave worktree
   (build\build_draglint_win64.bat -- check it deploys only into the worktree), full battery
   (tests\run_battery.ps1, ~75 min, quiet machine).
5. Merge wave/1315 -> main, announce to CONVERTER/CHARTS; dll-win64 redeploy + BPL deploy need
   owner "go" (BPL: RAD Studio closed); build installer 1.31.5; owner VM test (owner plans to run
   Claude on the VM); publish installer only.

## Proposed CHANGELOG lines (from lane reports)
- Fixed: a binary .dfm is reported "binary DFM (TPF0) -- save as Text DFM..." not "parse error (1,1)".
- Fixed: `index` no longer writes "FTS5 probe: AVAILABLE" to stderr (red NativeCommandError in PS 5.1).
- Fixed: used-unit-not-resolvable knows unscoped RTL/VCL names (ActiveX, ComObj, CommCtrl ...);
  neutral advice text instead of Orpheus/BDE hints.
- Fixed: Config tool Save writes only your edits into the file it opened; unmodelled keys kept; no
  merged local manifest written into the global file (B-22). migrate-dbs keeps unmodelled keys too.
- Fixed: `resolve-dbs --in` prints a stderr NOTE for an uncovered file instead of silence (B-20).
- Fixed: multi-project rename checks an owner against its compile closure; a transitively reached
  unit missing from the index refuses the rename instead of a partial apply + broken build (B-03).
- Fixed: object-leak ignores `TArray<T>.Create`; used-before-assignment: `with Rec do` on a record
  local is not a use (class local still fires).
- Plugin: job timeouts enforced while the engine runs; on expiry the process tree is killed and the
  job shows "timed out after N s"; a rename with stale owners gets 600 s per owner (B-19).
- Fixed: index into a new database no longer prints the no-resolver-stamp / no-scan_type notes or 'limit 0'; the whole-DB reason gives real new/changed counts; the ~37-min warning prints only from 1M refs (DRAGLINT_WHOLEDB_SLOW_REFS overrides) (V-C). [lane 2, MERGED]
- Fixed: allow accepts a whole-routine metric marker where lint reports it (large files, nested routines, multi-line headers) -- lint/lint-all/allow share RoutineMetricFindings (B-10, B-11); an allow batch on a wrapped statement no longer deletes the continuation line's marker (B-12); lint-all refuses --file/--in (exit 2) instead of ignoring it. [lane 7, MERGED]
- Fixed: document --apply keeps a managed facts block it cannot see when a hand-written summary leaves no fence (B-05 residue); shared units converge -- a certain caller is never downgraded to ' ?' by a project that cannot resolve it, ending the YADF/YADFOT rewrite loop (B-06); regeneration keeps the legacy Pure para the checker accepts (B-07). [lane 6, MERGED -- ALL 9 LANES MERGED]
- Lane 6 follow-ups: lint --fix --apply without --project-rules silently skips doc-drift fixes; 'declaration' as a Used-by caller name; YADFOT new DB reports 162/174 files outside closure.
- Lane 2 follow-ups: watch-mode FScopeWhole latch never reset between ticks; prune ids counted as 'changed' in the reason.

## Gotchas
- Never build on main: build bat deploys to the shared third_party\dll-win64 (needs owner go).
- Lane 8 changed stored symbol_facts via ExprIsConstructor (not on the extractor hash surface):
  deferred to the 1.22 full re-parse; add Analysis.Flow.Lattices.pas to the surface then (in plan).
- docs-sync / rename-owners guards default -Exe to <worktree>\third_party\dll-win64 -- pass -Exe.
- Backlog-index guard FAILS on pre-existing count drift (not ours); recount is in wave 2.
- Cleanup needing approval: broken worktree folder `.claude\worktrees\agent-a093407ae7ae356a5`;
  merged lane worktrees `.claude\worktrees\agent-*` can be removed after the wave.
- stash@{0} is the owner's (P3 YADF reformat) -- keep.
