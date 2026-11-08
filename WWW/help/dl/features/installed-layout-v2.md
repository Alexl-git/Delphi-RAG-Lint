---
id: installed-layout-v2
title: manifest where / migrate (installed layout v2)
summary: Shows which drag-lint.json this engine reads and why; moves the exe-side one to %APPDATA% once (renamed, never deleted). Installed layout v2, off by default
product: DL
group: maintenance
order: 120009
since: 1.47.0-alpha
status: shipped
updated: 1.47.0-alpha
---

# manifest where / migrate (installed layout v2)

Shows which drag-lint.json this engine reads and why; moves the exe-side one to %APPDATA% once (renamed, never deleted). Installed layout v2, off by default.

Read this when you need to know which manifest an engine would read. manifest where is read-only. The new layout is off unless DRAGLINT_LAYOUT=v2; an explicit manifest (DRAGLINT_MANIFEST or --manifest) wins in both layouts, and a missing explicit file never falls through to another manifest.

## How to run it

```text
drag-lint manifest where [--manifest <path>] [--json] (read-only: which drag-lint.json, log folder and library folder this engine resolves, and each lookup rung. Order: explicit DRAGLINT_MANIFEST / --manifest, then with DRAGLINT_LAYOUT=v2 the file in %APPDATA%\drag-lint, then beside the exe. Creates, moves and renames nothing)
```

Full flag list: [manifest in the CLI reference](../cli.md#manifest).

```text
drag-lint manifest migrate [--apply] [--json] (one-time, installed layout v2 phase 2: without --apply plans and touches nothing; with --apply and DRAGLINT_LAYOUT=v2 writes %APPDATA%\drag-lint\drag-lint.json with outDir and relative includes made absolute, so every DB stays put, then RENAMES the exe-side file to drag-lint.json.migrated-<date>. Never deletes, never overwrites. Exit 0 done / would / nothing to do, 2 refused, 1 failed)
```

Full flag list: [manifest in the CLI reference](../cli.md#manifest).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--manifest` | `path` |  |  |
| `--json` |  |  |  |
| `--apply` |  |  |  |
| `--json` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

The installed layout v2 moves user data out of the program folder: the manifest to
`%APPDATA%\drag-lint`, logs and library DBs to `%LOCALAPPDATA%\drag-lint`. **Phase 1 only resolves
paths; phase 2 adds the one-time `manifest migrate`.** It is off by default, and nothing is moved
until you run `manifest migrate --apply` with the switch on.

Design: `docs\superpowers\specs\2026-11-06-installed-layout-v2.md`.

### See what this engine resolves

```text
drag-lint manifest where [--manifest <path>] [--json]
```

Read-only. It prints the layout, the manifest file with its origin (`explicit`, `appdata` or
`exe-dir`), every lookup rung with whether it exists and is active, the log folder and the library
folder. It exits 0 even when the file does not exist.

### The lookup

1. **Explicit:** `--manifest <path>` (any verb that uses the shared flags), then `DRAGLINT_MANIFEST`.
   Honoured in both layouts. A missing file is reported and answers with no sections: it never falls
   through to another manifest. The flag reaches spawned index children.
2. **`%APPDATA%\drag-lint\drag-lint.json`**, only with `DRAGLINT_LAYOUT=v2` and only if the file exists.
3. **`drag-lint.json` beside the exe.**

`--config <file>` still names one file for one verb and bypasses the lookup. A local
`.drag-lint.json` still merges over whichever file answered. Relative paths resolve against the folder
the file was found in.

### Move the manifest: `manifest migrate`

```text
drag-lint manifest migrate [--apply] [--json]
```

Without `--apply` it only plans: it names the exe-side file, the roaming target and the name the old
file would get, and touches nothing (allowed with the switch off). With `--apply` and
`DRAGLINT_LAYOUT=v2` it writes `%APPDATA%\drag-lint\drag-lint.json` and then RENAMES the exe-side file
to `drag-lint.json.migrated-<yyyy-mm-dd>` (`-2`, `-3` when that name is taken). It never deletes and
never overwrites.

Every DB stays where it was: the written `outDir` is absolute (the exe folder when it was absent) and
every relative section `include` becomes absolute against the exe folder. Every other key is kept.

Exit codes: 0 migrated, would migrate, or nothing to migrate; 2 refused (the roaming file exists,
`--apply` with the switch off, an explicit manifest in effect, `%APPDATA%` unset); 1 failed. The
BPL-side copy is not touched (the plugin moves in phase 3).

### With `DRAGLINT_LAYOUT=v2`

- `register-project` and the manifest-rewriting verbs write the file the lookup answered. When no
  manifest exists anywhere, `register-project --apply` creates `%APPDATA%\drag-lint\drag-lint.json`.
- `%NAME%` references in `outDir` expand (an unset name, a lone `%` and `%%` stay literal). With the
  switch off `outDir` is literal, as before.
- A manifest read from `%APPDATA%\drag-lint` with no `outDir` puts DBs in
  `%LOCALAPPDATA%\drag-lint\library`; any other manifest with no `outDir` keeps them beside itself.
- The fatal log goes to `%LOCALAPPDATA%\drag-lint\logs`.
- `DRAGLINT_LAYOUT=v1` (or any value other than `v2`) is the flat layout; it stays the way back
  after the default flips.

Do not set the switch on a machine with the IDE plugin yet. The plugin still reads the manifest
beside the BPL or exe, so the two would disagree.

### Not in this phase

The plugin lookups (phase 3) and the installer changes (phase 4, behind the `LAYOUT_V2` build
define, off) come later. A VM test is owed before the default can change (phase 5).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
