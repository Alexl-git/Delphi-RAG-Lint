## v0.39.0-alpha — plugin diagnostic menu

Two new Tools menu entries so you can diagnose the LSP handshake failure in **one click** without touching log files manually.

### `Tools → drag-lint → Test Connection...`

Runs the same Start + Initialize sequence the plugin uses internally and shows a ShowMessage report with:

- The actual BPL path that's loaded
- The resolved `drag-lint.exe` candidate (next to BPL? on PATH?)
- Whether CreateProcessW succeeded
- Whether the initialize handshake completed
- Path to the detailed log file

Click it once. The report tells you exactly where the chain is breaking.

### `Tools → drag-lint → Open Plugin Log`

Opens `%TEMP%\drag-lint-plugin.log` in your default editor (Notepad usually).

### To install v0.39

The BPL is loaded into RAD Studio at startup, so:

1. **Component → Install Packages...** → uncheck `drag-lint` → OK (the package unloads from memory).
2. Replace `dclDragLintWizard.bpl` with the v0.39 version (from this zip).
3. **Component → Install Packages...** → re-check `drag-lint` → OK.

Or close RAD Studio entirely, replace the file, restart.

After install, **Tools → drag-lint → Test Connection...** is the fastest diagnostic path.
