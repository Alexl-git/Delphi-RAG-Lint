# Installed layout v2 (phase 1)

The installed layout v2 moves user data out of the program folder: the manifest to
`%APPDATA%\drag-lint`, logs and library DBs to `%LOCALAPPDATA%\drag-lint`. **Phase 1 only resolves
paths.** It is off by default, and no install, manifest or DB is moved.

Design: `docs\superpowers\specs\2026-11-06-installed-layout-v2.md`.

## See what this engine resolves

```
drag-lint manifest where [--manifest <path>] [--json]
```

Read-only. It prints the layout, the manifest file with its origin (`explicit`, `appdata` or
`exe-dir`), every lookup rung with whether it exists and is active, the log folder and the library
folder. It exits 0 even when the file does not exist.

## The lookup

1. **Explicit:** `--manifest <path>` (any verb that uses the shared flags), then `DRAGLINT_MANIFEST`.
   Honoured in both layouts. A missing file is reported and answers with no sections: it never falls
   through to another manifest. The flag reaches spawned index children.
2. **`%APPDATA%\drag-lint\drag-lint.json`**, only with `DRAGLINT_LAYOUT=v2` and only if the file exists.
3. **`drag-lint.json` beside the exe.**

`--config <file>` still names one file for one verb and bypasses the lookup. A local
`.drag-lint.json` still merges over whichever file answered. Relative paths resolve against the folder
the file was found in.

## With `DRAGLINT_LAYOUT=v2`

- `register-project` and the manifest-rewriting verbs write the file the lookup answered. They do
  not create one.
- The fatal log goes to `%LOCALAPPDATA%\drag-lint\logs`.
- `manifest where` reports `%LOCALAPPDATA%\drag-lint\library` as the library folder. No DB goes there
  yet: the manifest's `outDir` still decides.

Do not set the switch on a machine with the IDE plugin yet. The plugin still reads the manifest
beside the BPL or exe, so the two would disagree.

## Not in this phase

`manifest migrate`, `outDir` environment-variable expansion, the plugin lookups and the installer
changes come later. A VM test is owed before the default can change.
