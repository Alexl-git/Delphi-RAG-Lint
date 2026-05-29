## v0.26.0-alpha -- 2026-05-29

### Added — compiler diagnostic integration (replaces Error Insight)

The pipeline that lets the plugin replace RAD Studio's Error Insight with
the real dcc32/dcc64 H/W/E/F output. Four components ship in v0.26:

- **\drag-lint compile-check <target>\** -- runs the appropriate
  compiler against a \.dproj\ (msbuild) or \.pas\ (dcc64 -Q -B),
  parses every H/W/E/F line, and INSERTS into the v0.8 \compiler_findings\
  table. Output: text summary or \--format json\. Exit codes:
  0 success, 1 errors found, 2 spawn failed.

- **LSP \publishDiagnostics\ now merges compiler findings.** When the
  IDE plugin (or any LSP client) saves a file, the editor's diagnostics
  panel includes BOTH our lint findings AND any compiler findings in the
  database for that file. Source tags: \'drag-lint'\ for lint,
  \'dcc'\ for compiler.

- **MCP \un_compile_check\ tool** -- Claude/Cursor/etc. can request
  a compile, get back the structured finding array. Tool 13 in our
  catalog. Args: \{target, msbuild_path?, db?}\.

- **Plugin Tools menu adds two entries**:
  - \Tools > drag-lint > Compile && Diagnose\ -- spawns msbuild against
    the active project's .dproj, captures output, persists findings,
    broadcasts \	extDocument/didSave\ to refresh the LSP diagnostics
    view for every affected file. Shows a summary dialog.
  - \Tools > drag-lint > Import Build Log...\ -- TOpenDialog to browse
    for a saved msbuild/dcc output file; parses, persists, broadcasts
    didSave.

### Notes

- Single-file \.pas\ compile-checks can fail when cross-unit dependencies
  aren't available. That's expected -- the parser still ingests the
  resulting errors so you see what would need to be fixed.
- \Clear Compiler Findings\ Tools menu entry is deferred to v0.27
  to avoid pulling FireDAC into the design-time plugin.
- Refactor preview form (originally v0.25 F1, then v0.26 carry-over)
  is deferred again to v0.27. The InputBox + ShowMessage flow from
  v0.24 still works; v0.27 will give it a proper VCL form.
