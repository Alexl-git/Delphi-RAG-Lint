## v0.37.0-alpha — critical SQL fix on top of v0.36 architecture fix

Two-part critical fix sequence: v0.36 fixed the binary architecture mismatch (Win32 exe trying to load Win64 DLLs), and **v0.37 fixes a follow-up bug that surfaced once Win32 binaries could actually run**.

### What v0.37 fixes

`drag-lint index` was failing on Win32 with `[FireDAC][Phys][SQLite] ERROR: near "ON": syntax error`. The `FQUpsertFile` prepared query used SQLite's UPSERT syntax (`INSERT ... ON CONFLICT(col) DO UPDATE SET ...`) which requires SQLite 3.24+ (June 2018). **RAD Studio 13's bundled Win32 FireDAC SQLite library is older** than that and rejects the keyword. Win64 FireDAC ships a current-enough SQLite and was unaffected.

Without this fix, the IDE plugin's auto-index on project open would fail immediately, making v0.36's dual-arch progress useless in practice.

### Both fixes are required for the IDE plugin

If you tested any prior release and saw indexing fail, this is the version to use. The Win32 zip below contains the matched-arch binaries (v0.36 fix) **and** the SQL fix (v0.37).

### Download

**Win32 bundle for RAD Studio 13 IDE plugin:** `drag-lint-v0.37.0-alpha-win32.zip` (~6.3 MB)
- `drag-lint.exe` + 3 tree-sitter DLLs (all PE32)
- `dclDragLintWizard.bpl`
- README.md, CHANGELOG.md, LICENSE

**Win64 bundle for standalone CLI/LSP/MCP:** `drag-lint-v0.37.0-alpha-win64.zip` (~5.5 MB)
- `drag-lint.exe` + 3 tree-sitter DLLs (all PE32+)
- No BPL
