# Two-DB Model Design (6.3)

**Date:** 2026-06-26
**Status:** Approved — ready for implementation
**Approach:** B — infer platform vs project sections from existing manifest fields; no schema changes

---

## Problem

drag-lint currently requires explicit `--db` flags for every command. Users must manually specify
both the Project DB (e.g. `C:\Projects\DB\ORM3\drag-lint.sqlite`) and the Platform DB
(`C:\Projects\.drag-lint\library-Win64.sqlite`) on every invocation. The plugin partially
addresses this with `ResolveActiveIndexDbs()`, but uses the legacy merged
`drag-lint-library.sqlite` (Win32-only) instead of the per-platform library files.

**Goal:** By default, every drag-lint command works with two DBs — Project + Platform — with no
`--db` flags required. Platform is detected from OTAPI live in the plugin, or from the `.dproj`
file in CLI standalone mode.

---

## Platform DB files (confirmed present)

| File | Size | Path |
|---|---|---|
| `library-Win32.sqlite` | 907 MB | `C:\Projects\.drag-lint\library-Win32.sqlite` |
| `library-Win64.sqlite` | 850 MB | `C:\Projects\.drag-lint\library-Win64.sqlite` |

Both are fully indexed. No re-scan needed.

---

## Manifest — no schema changes

The existing `drag-lint.json` already encodes the distinction:

- **Platform section** — identified by `"source": "registry-libraries"` (unique; no project section
  has this field). Its `"db"` value is a template: `"library-{platform}.sqlite"`. Resolved against
  `indexes.outDir` (`C:\Projects\.drag-lint\`).
- **Project section** — identified by presence of `"include"` paths. Its `"db"` value is an
  absolute path to a project-specific SQLite file.

No new fields (`"type"`, etc.) are added. Backward compatibility is fully preserved.

---

## Design

### 1. CLI auto-resolution (standalone, no IDE)

Trigger: any subcommand runs with zero `--db` flags.

Resolution steps (executed inside the existing `resolve-dbs` code path):

1. **Project DB** — find the manifest section whose `include` path is an ancestor of (or equal to)
   the CWD. If multiple sections match (nested includes), use the **most specific** (longest
   prefix) match. Use that section's `db` value. If no section matches, emit a clear error:
   `"No project section covers the current directory. Use --db to specify explicitly."`.

2. **Platform DB** — find the manifest section with `"source": "registry-libraries"`. Substitute
   the detected platform into `{platform}` in its `db` template. Resolve against `outDir`.

3. **Platform detection order:**
   a. `--platform <Win32|Win64>` flag (explicit override — already exists on `resolve-dbs`,
      propagated to all other subcommands by this change)
   b. First `.dproj` found under the matching project section's `include` directory — parse
      `<Platform Condition="'$(Platform)'==''">` XML element
   c. `settings.defaultPlatform` from manifest (currently `"Win32"`)

   Example: ORM3 CLIENT `.dproj` has `<Platform ...>Win64</Platform>` → picks
   `library-Win64.sqlite`.

4. **Result:** both DBs are loaded in order — Project first, Platform second — matching the
   priority order already used by `resolve-dbs`.

### 2. `index` command special case

`index` with no `--db` auto-selects the **Project DB only**. The platform DB contains read-only
Delphi RTL/VCL/DevExpress symbols and is never reindexed by the user-facing `index` command.
`index --all` already handles the `"Library"` section separately and is unchanged.

### 3. Plugin side — `DbResolver.pas`

Current behaviour: `ResolveActiveIndexDbs()` includes `drag-lint-library.sqlite` (legacy merged
Win32-only file beside the exe) when `IncludeLibraryDb = True`.

New behaviour:
1. Read `GetActiveProjectPlatform()` — already implemented; calls `IOTAProject.CurrentPlatform`
   live from OTAPI (returns `'Win32'` or `'Win64'`).
2. Read the manifest's `indexes.outDir` (already loaded by `ManifestDbForFile`).
3. Find the manifest section with `"source": "registry-libraries"`.
4. Substitute `{platform}` in its `db` template → `library-Win64.sqlite` (for ORM3 Win64
   projects).
5. Resolve against `outDir` → `C:\Projects\.drag-lint\library-Win64.sqlite`.
6. Use this resolved path instead of the hardcoded `drag-lint-library.sqlite`.

`IncludeLibraryDb` remains `True` by default — no change to the settings default.

No changes to individual CLI invocation sites in the plugin. `ResolveActiveIndexDbs()` is the
single resolution point; callers already receive the resolved DB list.

### 4. `--platform` flag propagation

Already present on `resolve-dbs`. Add it (optional, no default) to:
`query`, `lint`, `forms-csv`, `lint-project`, `lint-all` (future).

When provided, it overrides step (b) of platform detection. The plugin never needs this flag — it
always passes resolved `--db` paths explicitly. This flag is for CLI standalone users switching
platform context (e.g. `drag-lint query --name TFoo --platform Win32`).

---

## Files to change

| File | Change |
|---|---|
| `src\cli\DRagLint.CLI.pas` | Auto-resolve Project + Platform DB when no `--db`; add `--platform` to query/lint/forms-csv/lint-project; `index` selects Project DB only |
| `src\delphi-plugin\DragLint.Plugin.DbResolver.pas` | Replace `drag-lint-library.sqlite` with manifest-resolved `library-{OTAPI platform}.sqlite` |
| `third_party\dll-win64\drag-lint.json` | No changes |

---

## Out of scope

- Build configuration (Debug/Release): not needed for DB selection; may be relevant for
  `compile-check` but that is a separate concern.
- `index --all`: unchanged — already handles Library section separately.
- iOSSimulator and other non-Windows platforms: not in scope (Win32/Win64 only).
- New manifest fields (`"type"`, `"platformDb"`, etc.): rejected as redundant.
