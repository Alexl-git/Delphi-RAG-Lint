## v0.38.0-alpha — LSP debug log + cmd-line fixes

The IDE plugin now writes a detailed log of every LSP subprocess event to **`%TEMP%\drag-lint-plugin.log`**. When you see "LSP initialize handshake failed" or "LSP server failed to start", the error dialog now includes the log file path so you can see exactly what's happening.

### Three related fixes

1. **Quote the exe path** in CreateProcessW cmd-line. Previously `<path> lsp` was tokenized by Windows; if the BPL was installed at a path containing spaces, the spawn either failed or spawned the wrong process.

2. **CREATE_NO_WINDOW** added so the subprocess doesn't pop a console window.

3. **Initialize timeout bumped 5s → 10s** for slower disks / cold starts.

### To pick up the v0.38 BPL

The BPL is loaded into RAD Studio's process memory at IDE startup. Pick **one** of these to update:

- **A**: Close RAD Studio entirely → replace `dclDragLintWizard.bpl` → restart.
- **B**: Component → Install Packages → uncheck drag-lint → OK → replace BPL → re-check.

### To diagnose the handshake failure

After installing v0.38 BPL and reproducing the error:

1. Click OK on the "handshake failed" dialog.
2. Open the log: `%TEMP%\drag-lint-plugin.log` (in Notepad: paste that into Run dialog).
3. Look for entries like:
   - `Start: ExePath=... (FileExists=true/false)` — was the binary found?
   - `Start: CreateProcessW FAILED, GetLastError=N` — spawn-level failure
   - `ReaderThread: ReadFile failed/EOF` — subprocess died early
   - `Initialize: TIMEOUT or no response within 10s` — subprocess running but not responding
4. Share that log (or the relevant lines) for diagnosis.
