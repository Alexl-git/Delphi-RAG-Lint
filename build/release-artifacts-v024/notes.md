## v0.24.0-alpha -- 2026-05-29

### Added (Refactoring)

- **`drag-lint rename --qname Foo.TBar.Baz --to NewName`** -- rewrites
  every occurrence of a symbol. Uses the existing index's
  declaration site + `FindCallersByName` results. Edits are sorted
  back-to-front so applying them doesn't shift columns mid-pass.
  Source files are written back as ANSI + CRLF to preserve the
  project's strict-ASCII conventions. A `.bak` backup is written before
  each file mutation unless `--no-backup` is passed. `--dry-run` shows
  the diff without writing. Exit codes: 0 success, 1 not-found,
  2 collision, 3 I/O error.

- **MCP tool `rename_symbol`** -- same as the CLI, callable from
  Claude/Cursor/etc. Args: `{qname, to, dry_run?, db?}`. Returns
  `{edits: [...], files_touched: N, applied: bool}`. Total MCP tool
  count is now 12.

- **Plugin Tools menu `Rename Symbol...`** -- two InputBox prompts
  (qname + new name) and shows the equivalent CLI command. v0.24
  plugin is dry-run only -- full integration (synchronous spawn +
  apply on confirm) moves to v0.25 polish. Keystroke `Ctrl+Alt+R`.

### Notes

- Rename is name-based, not inheritance-aware. Overrides that share
  the same name will be renamed; symbols in unrelated classes with the
  same short name will ALSO be renamed (since `FindCallersByName` is
  name-based, not symbol-id-based). v0.22+ remains parked on
  populating `refs.symbol_id` for precision; once that lands the
  rename can become id-based.
- DFM event-handler bindings (`OnClick = btnOKClick` etc.) are indexed
  as `event-binding` refs in v0.16; the rename catches those too
  because `FindCallersByName` returns them. Saving forms after a
  rename will then sync the .dfm with the .pas.