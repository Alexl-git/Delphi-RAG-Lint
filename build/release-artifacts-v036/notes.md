## v0.36.0-alpha — critical architecture fix

**This release fixes a critical bug present in v0.16-v0.35**: the bundled `drag-lint.exe` (Win32) was paired with Win64 `tree-sitter*.dll` files. The exe would silently fail to load the DLLs with `STATUS_INVALID_IMAGE_FORMAT` (0xC000007B), making every prior release effectively non-functional.

### Download

**For RAD Studio 13 IDE plugin use:** download `drag-lint-v0.36.0-alpha-win32.zip`. The IDE is a 32-bit process so the BPL + companion binaries must all be Win32.

**For standalone CLI / LSP / MCP use** (no IDE plugin): download `drag-lint-v0.36.0-alpha-win64.zip`. Faster + more memory headroom for indexing large codebases.

### Bundle contents

**Win32 bundle** (~6.5 MB zip → ~30 MB extracted):
- `drag-lint.exe` (PE32 / Intel i386)
- `tree-sitter.dll`, `tree-sitter-delphi13.dll`, `tree-sitter-dfm.dll` (all PE32 / Intel i386)
- `dclDragLintWizard.bpl` (Win32 — the IDE design-time package)
- README.md, CHANGELOG.md, LICENSE

**Win64 bundle** (~5.7 MB zip → ~25 MB extracted):
- `drag-lint.exe` (PE32+ / x86-64)
- `tree-sitter.dll`, `tree-sitter-delphi13.dll`, `tree-sitter-dfm.dll` (all PE32+ / x86-64)
- README.md, CHANGELOG.md, LICENSE
- No BPL — can't load into the 32-bit RAD Studio IDE process

### Verify after install

After extracting either zip and putting it on PATH, run:
```
drag-lint --version
```
Expected output: `drag-lint 0.36.0-alpha`. If you get exit code -1073741701 instead, your DLL bitness doesn't match the exe.

### Build scripts (for source builds)

Six new scripts under `build/`:
- `build_draglint_win32.bat` / `build_draglint_win64.bat` — Delphi 13 msbuild
- `_buildruntime32.bat` / `_buildruntime64.bat` — tree-sitter runtime DLL via cl.exe
- `_buildgrammar32_manual.bat` / `_buildgrammar64_manual.bat` — tree-sitter-delphi13.dll from parser.c + scanner.c
- `_builddfm32_manual.bat` / `_builddfm64_manual.bat` — tree-sitter-dfm.dll from parser.c

All other v0.35 features unchanged. See the full version history in CHANGELOG.md.
