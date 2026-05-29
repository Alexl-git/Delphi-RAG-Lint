## v0.27.0-alpha -- 2026-05-29

### Added

- **`drag-lint generate-test --qname X [--framework dunitx|dunit]`** --
  emits a DUnitX (or DUnit) test scaffold for the given symbol.
  Builds `T<Class><Method>Tests` with `[TestFixture]` + `[Test]`
  attributes, HappyPath body instantiates the subject + asserts via
  `Assert.AreEqual`, EdgeCases body has a TODO.

- **`drag-lint format <file> [--yadf-path PATH]`** -- shells to YADF
  (https://github.com/Alexl-git/YADF) for in-place .pas/.dpr/.dpk
  formatting. Auto-detects YADF.exe via `HKCU\Software\YADF\ExePath`
  registry, then `C:\Projects\YADF\Win32\Release\EXE\YADF.exe`
  fallback. 30s timeout.

- **Plugin: Refactor preview form** (`DragLint.Plugin.RefactorForm`)
  replaces the v0.24 two-`InputBox` flow with a proper VCL modal
  dialog. Symbol qname + new name fields, Write .bak checkbox,
  Preview button (runs `drag-lint rename --dry-run` and shows the
  edit list in a memo), Apply button (enabled only after a successful
  preview; confirms via MessageDlg before applying).

- **Plugin Tools menu `Format with YADF`** -- shells `drag-lint format
  "<active-file>"` and shows YADF stdout summary. User saves manually
  before running.

### Notes

- Test stub generation is name-based -- the suggested class instantiation
  doesn't import the unit; you'll need to add the `uses` clause yourself.
- YADF format runs in-place. If the file has unsaved IDE buffer changes,
  YADF formats the on-disk version while the IDE buffer remains stale.
  Future v0.28+ may integrate Save-before-Format.
- Refactor preview dialog still calls drag-lint.exe as a subprocess
  rather than direct interop. Keeps the design-time package small.

---
