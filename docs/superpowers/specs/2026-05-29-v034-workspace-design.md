# v0.34 — Workspace Mode (multi-project)

**Date:** 2026-05-29
**Status:** Design approved
**Branch:** `v0.34-workspace` off `main`

## 1. Goal

Index multiple related projects into a single drag-lint database. Useful
for a multi-project repo like Micronite ORM3 (PACKAGE + SERVER +
CLIENT + COMMON) where symbols cross project boundaries.

## 2. Workspace config

A new file `.drag-lint-workspace.json` at the workspace root:

```json
{
  "name": "Micronite ORM3",
  "projects": [
    {"path": "PACKAGE/Interfaces.dproj"},
    {"path": "SERVER/MicroniteMW1Service.dproj"},
    {"path": "CLIENT/Micronite2027.dproj"},
    {"path": "COMMON", "scan_dir": true}
  ],
  "shared_db": ".drag-lint-workspace.sqlite"
}
```

Schema:
- `name`: human label
- `projects`: array of objects with:
  - `path`: relative path to .dproj OR directory
  - `scan_dir`: if true, recursively scan the directory (instead of using
    project deps)
- `shared_db`: relative path to the single shared SQLite file

## 3. CLI surface

### `drag-lint workspace index [--config PATH]`

1. Discover workspace.json (current dir, or walk up; or `--config PATH`)
2. For each project: spawn the existing `drag-lint index` against that
   path, all writing to the same shared DB
3. Progress to stdout

### `drag-lint workspace status [--config PATH]`

Lists projects + last-indexed timestamps from `files.parsed_at`.

### `drag-lint workspace add <projfile> [--config PATH]`

Appends a project to the workspace.json.

## 4. Storage

No schema change. The existing `files.path` column stores absolute
paths, so multiple project roots in one DB just produces a flat file
table.

## 5. New module

- `src/workspace/DRagLint.Workspace.Config.pas`
  - `TWorkspaceConfig` record
  - `LoadFromFile(path)` / `SaveToFile(path)`
  - `FindWorkspaceRoot(startDir): string` (walks up looking for
    .drag-lint-workspace.json)

## 6. Plugin integration

In `DragLint.Plugin.ProjectNotifier.FileNotification`:

1. When .dproj opens, also try to find a workspace.json by walking up
2. If workspace found: spawn `drag-lint workspace index --config <ws>`
   instead of single-project index
3. The shared DB path replaces the per-project DB path

Settings: `EnableWorkspaceMode` (default True — opportunistic
detection; non-workspace projects fall back to per-project DB).

## 7. New CLI command

In `src/cli/DRagLint.CLI.pas`:

```pascal
function DoWorkspace(const AArgs: TArgs): Integer;
```

Sub-commands: `index`, `status`, `add`.

## 8. MCP

`workspace_status` tool returns the workspace config + per-project
last-indexed times.

## 9. Stop criteria

### Auto-verifiable

1. T59 — workspace config load/save round-trip.
2. T60 — `drag-lint workspace index` on a 2-project fixture indexes
   both into one DB.
3. BPL builds clean.

### Manual

4. Plugin detects workspace.json in parent of active .dproj and
   spawns workspace-index.

## 10. Out of scope (v0.35+)

- Workspace-aware refactoring (rename across all projects)
- Workspace tree view (custom dockable)
- Per-project filtering in query results

## 11. Push cadence

Spec → push. F1 + F2 → push. Tag + release.
