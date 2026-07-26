# Project index/findings coherence -- self-healing reconcile (design)

**Date:** 2026-07-19
**Status:** approved (brainstorm) -- ready for implementation plan
**Components:** `src/cli/` (extend the existing `reconcile-project` verb -- see revision), `src/delphi-plugin/` (triggers + buffer-change stamp)
**Motivating bug:** VARINSPCODE.pas (edited today) was absent from the ORM3-root index the LSP reads, so its DCC diagnostics never rendered. Root cause: an edited/new project member is not reindexed into the LSP's DB until a whole-project rescan.

> **DESIGN REVISION (2026-07-19, user):** the capability below is delivered by
> EXTENDING the existing `reconcile-project` verb with an opt-in `--db [--full]`
> phase, NOT by adding a separate `reconcile` verb. `reconcile-project` already
> reconciles the `.dpr` member list vs the compile closure (edits the `.dpr` with
> `--apply`); the new `--db` phase heals the drag-lint DB (index + findings) to match
> those members (never edits the `.dpr`). Both phases are independently opt-in. The
> member set reuses the project-owned compile closure `reconcile-project` already
> computes. Everywhere below that says "new `reconcile` verb", read "`--db` phase of
> `reconcile-project`" -- the behavior is identical, only the surface changes. See the
> implementation plan for the task breakdown.

## Invariant (the goal)

**Every project member must always be indexed and compiled, and its diagnostics must reflect the current source (saved OR in-IDE buffer).** Any drag-lint component that discovers missing / stale / uncompiled data for a member triggers a refresh (rescan + recompile). This is a self-healing coherence guarantee, not a one-shot trigger.

## Definitions

**Project members** = the compilable closure declared by the `.dpr`/`.dproj`: every unit named in the project's `unitname in '<path>'` uses entries (project-owned source), PLUS each unit's sibling `.dfm` when present. RTL/VCL/third-party units are NOT members (external). Bounded and authoritative (it is what the compiler sees).

**Per-member coherence state** (from the `files` table; columns already exist -- `id, path, mtime_unix, sha256, parsed_at, language, last_compiled_unix`):
- **Indexed** -- a `files` row exists (has a `file_id`).
- **Index-fresh** -- `files.mtime_unix` matches the disk file's mtime (timestamp-based per the decision; `sha256` is a fallback tiebreaker only).
- **Compiled-fresh** -- `files.last_compiled_unix >= files.mtime_unix`.
- **Buffer-dirty** -- the IDE has unsaved edits: the plugin's per-file buffer-change timestamp (see below) is newer than the disk mtime.

A member is **incoherent** if it is missing, index-stale, compile-stale, or buffer-dirty. VARINSPCODE.pas today = *missing* -> incoherent.

## Staleness: timestamps (not sha)

- **Saved changes** -- disk `mtime_unix`, compared to `files.mtime_unix` (index) and `files.last_compiled_unix` (compile).
- **Unsaved in-IDE edits** -- the OTA exposes no native buffer-content timestamp, so the plugin synthesizes one: `TDragLintEditViewNotifier.Modified` already fires on every edit-batch (EditViewNotifier.pas:170) -> stamp `Now` per file in an in-memory map (`GBufferChangeTick[file]`). `IOTAEditBuffer.IsModified` gives the clean/dirty flag. Together these tell the plugin a member's buffer is newer than its indexed/compiled state.

## In-buffer diagnostics without saving: reuse ghost-check

The plugin already has a **ghost-check / buffer-compile** mechanism (DragLint.Plugin.LiveDiagnostics.pas + `RunGhostCheckAsync`; `RunGhostRecoverForProject` restores originals if interrupted): it snapshots the unsaved buffer, temporarily overlays it to disk, compiles it (real DCC errors like E2003 appear), then restores the original file. This yields IDE-Error-Insight-equivalent compiler diagnostics on in-buffer code **without a permanent save**.

- **No auto-save.** The user may hold WIP they do not intend to save; reconcile must never write it. Fresh DCC on an unsaved buffer comes from the ghost-overlay (compile a temporary copy, restore), never from saving.

## The `reconcile` capability (drag-lint CLI)

New verb: `drag-lint reconcile --project <X.dproj> --db <db> [--full] [--json]`. Headless + testable (matches the existing `refresh-findings` pattern). Steps:

1. **Enumerate members** from the `.dpr` (unit paths) + each unit's sibling `.dfm`.
2. **Compute the incoherent set** -- run the coherence checks (indexed / index-fresh / compiled-fresh) for each member against `<db>` (the plugin passes buffer-dirty members explicitly; the CLI itself is disk-based).
3. **Scan** (index, incremental) every missing / index-stale member AND its `.dfm` into `<db>` -- this restores `file_id`s so findings can attach (the direct fix for the motivating bug).
4. **If any member was incoherent, trigger a FULL recompile** (reuse the `refresh-findings --full` engine) -> refreshes ALL compiler findings into the same `<db>` (per the "always full recompile on any staleness" decision).
5. Emit a summary: members, incoherent count, scanned, recompiled (text + `--json`).

The verb reuses the existing indexer (`Indexer.IndexFile`) and the refresh-findings compile+capture engine -- no new compile machinery. `--full` forces the full recompile regardless (the plugin passes it when staleness is detected).

## Plugin: one coalesced entry point + triggers

A single API: **`RequestProjectReconcile(projectPath)`** -- debounced + coalesced through the existing R2 job queue (`CoalesceKey='reconcile:<db>'`), spawned async so the full rebuild never blocks the IDE (one reconcile at a time). It resolves the DB via `ManifestDbForFile`/`ResolveActiveIndexDbs[0]` -- always the DB the LSP reads (so scans + findings never land in an orphan per-project DB, the root of the bug).

**Phase 1 triggers:**
- **Project open** (`.dproj`) -- replace today's plain whole-project `SpawnIndexer` with `RequestProjectReconcile` (scan-completeness + full compile).
- **Module added / source file opened that is not in the index** -- in `TDragLintProjectNotifier.FileNotification` (`ofnFileOpened`), when a `.pas` opens whose path is not in the manifest DB, call `RequestProjectReconcile` (reconcile detects the new/missing members -> scans + full recompile). This is what self-heals a VARINSPCODE-style file the moment it is opened.
- **Buffer-change stamp** captured on `EditViewNotifier.Modified` (marks members buffer-dirty / recompile-pending). The EXISTING active-buffer ghost-check continues to provide live DCC for the file being edited.

This one API IS the "any component that discovers staleness triggers a refresh" mechanism -- Phase 2 just adds more callers.

## Scope: Phase 1 (this spec) vs Phase 2 (later)

**Phase 1 (this spec):**
- The `reconcile` CLI verb (member enumeration + coherence delta + incremental scan of missing/stale members + `.dfm` + always-full recompile via refresh-findings engine, into the manifest DB).
- `RequestProjectReconcile` (coalesced, async) wired at project-open and module-added/file-open-not-indexed.
- The per-file buffer-change timestamp (`EditViewNotifier.Modified` -> `GBufferChangeTick`) + using it to mark recompile-pending.
- Delivers the invariant for saved state + full index completeness; the existing active-buffer ghost-check covers live DCC for the edited file.

**Phase 2 (later spec):**
- Full-project ghost-overlay build: overlay ALL buffer-dirty members -> one full build -> restore, for project-wide buffer-fresh DCC (extends the single-buffer ghost-check).
- Wire additional self-healing callers into `RequestProjectReconcile` (LSP file-lookup miss, hover, Full Compile Sweep, reverse-calltree, etc.).

## Testing

- **CLI `reconcile`** (headless autotest under `tests/autotest/`, matching `run_proptree*.ps1` / refresh-findings tests): a fixture project (`.dpr` with 2-3 units, one with a sibling `.dfm`, one deliberately absent from a pre-seeded DB). Assert: reconcile adds the missing member (+ its `.dfm`) to the DB; reports the incoherent count; a member whose mtime is newer than `last_compiled_unix` is flagged compile-stale; `--json` shape. Compile step gated/skipped cleanly when msbuild/project unavailable on a lean machine (skip-not-fail, per convention).
- **Membership parse** -- unit test the `.dpr`-uses -> member-path list (+ `.dfm` sibling resolution) in isolation.
- **Plugin triggers** -- headless-unverifiable (live IDE); the DB-target resolution (`ManifestDbForFile`) and the coalesce-key are unit-checkable; the rest is noted for a live-IDE smoke.

## Non-goals

- No auto-save of unsaved buffers (ever).
- No embedding of dcc in drag-lint (compile stays via msbuild / the ghost-overlay).
- Phase 1 does not do the full-project multi-buffer ghost-overlay build (Phase 2).
