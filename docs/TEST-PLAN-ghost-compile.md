# Test Plan: ghost-compile + live compiler diagnostics (v0.48)

Covers the work added 2026-06-18: out-of-process compile of UNSAVED code, the
auto-triggers, multi-unit overlay, crash recovery, gutter sync, and the
auto-jump-to-Diagnostics. Run in the IDE against a real project (e.g. ORM3
`Micronite2027.dproj`).

## 0. Setup
- [ ] Close RAD Studio, confirm the deployed BPL is current: `third_party\dll-win32\dclDragLintWizard.bpl` timestamp is today (>= the latest commit). The engine `third_party\dll-win32\drag-lint.exe` is the multi-overlay build.
- [ ] Reopen RAD Studio and the project. (BPLs don't hot-reload -- a restart is required after any deploy.)
- [ ] Two logs help if something misbehaves:
      - plugin: `%TEMP%\drag-lint-plugin.log` (look for `Compile(state): ... START` / `exit`)
      - runner: `third_party\dll-win32\drag-lint-telemetry.log` (look for `[livediag] runner: ... idle -> auto ghost-check`, `switch settled`, `SKIP --` reasons)

## 1. Startup compile (AutoCompileOnStartup)
- [ ] With a project that has a known compiler error saved (e.g. an undeclared identifier), start the IDE.
- [ ] A few seconds after the project loads, the error appears in the drag-lint Diagnostics pane + a gutter mark -- WITHOUT any edit or save.
- [ ] Clean project -> no errors shown. (`/t:Make` is incremental, so this is fast.)

## 2. Auto-compile-on-idle (AutoCompileBuffer) -- the core feature
- [ ] Open a `.pas`, introduce a semantic error you do NOT save (e.g. a var of an undeclared type, or reference an undeclared identifier). Type a few chars; STOP.
- [ ] ~3-4s after you stop typing, the compiler error appears (Diagnostics list + gutter) although the file is still modified/unsaved.
- [ ] Telemetry shows `runner: idle -> auto ghost-check`. If it does NOT fire, the log now says why (`SKIP -- AutoCompileBuffer is OFF` / `hook not assigned` / `busy`).
- [ ] Keep typing then pausing -> it recompiles each time you settle (once per burst), never piles up.
- [ ] Fix the error (still unsaved) + pause -> the error clears.

## 3. Multi-unit overlay
- [ ] Edit unit A (introduce an error referencing something), DON'T save; switch to unit B and edit it too (also unsaved).
- [ ] Pause -> the compile reflects BOTH unsaved units (A's error shows even though you're now in B; B's unsaved code is seen too).
- [ ] Plugin log: `Compile(state): N overlay(s)` where N = number of unsaved units. (If N is large when only 1-2 are edited, tell me -- the `.pas` byte-diff is over-collecting.)

## 4. File-safety (the critical invariant)
- [ ] After ANY of the above auto-compiles, the edited file on disk is UNCHANGED: the IDE shows NO "file changed on disk, reload?" prompt, and your unsaved edits remain in the editor.
- [ ] (Optional, outside the IDE) note a unit's size + Last-Write time before; trigger a compile; confirm both are identical after.
- [ ] A hidden `_D-RAG` folder may appear beside the `.dproj` during a compile; after a clean run it has no `*.ghost-journal` / `*.ghost-orig` left.

## 5. Crash recovery
- [ ] (Simulated) While a buffer-compile is running, kill the engine (`drag-lint.exe`) in Task Manager mid-compile.
- [ ] The file may be left overlaid. On next IDE start, the project-open recovery restores the original automatically (no prompt) and posts a note to the Messages pane; the crash-time content is kept in `_D-RAG\<unit>.crash-buffer`. Menu fallback: "Recover Buffer-Compile Files".

## 6. Compile-on-tab-switch (AutoCompileOnSwitch)
- [ ] Switch from unit A to unit B (no edits). ~1.2s after settling, a compile runs (current state) and B's diagnostics show.
- [ ] Rapidly flip A/B/A -> it does NOT fire a compile per flip (debounced; single-flight).
- [ ] Telemetry: `runner: tab switch -> arm compile` then `switch settled -> compile current state`.

## 7. Auto-jump to Diagnostics (AutoJumpToDiagnostics)
- [ ] With the drag-lint dock/Structure panel open: after a compile that produces diagnostics, the Structure tree auto-scrolls so the "Diagnostics (N)" section is at the top and the first message is selected.
- [ ] After a compile with NO diagnostics, the Structure view does NOT jump (stays where you were).
- [ ] The manual "Diag" button still scrolls to Diagnostics on demand.

## 8. Gutter <-> list sync
- [ ] When the Diagnostics list updates, the gutter marks update in step (square dots, distinct from round breakpoint dots) -- no lag where the list shows an error but the gutter doesn't, or vice-versa.

## 9. Settings toggles (HKCU\Software\drag-lint\DelphiPlugin)
Each defaults ON; flip to 0, restart, confirm the behavior stops; flip back:
- [ ] `AutoCompileBuffer` (idle compile) · `AutoCompileOnStartup` · `AutoCompileOnSwitch` · `AutoJumpToDiagnostics` · `AutoCompileOnSave`.

## Known limitations (not bugs)
- DFM-only edits (e.g. deleting a `TEdit` in the designer without touching the
  `.pas`) are NOT yet reflected -- DFM overlay is Phase 2 (`docs/BACKLOG-ghost-dfm.md`).
- Warnings/hints only re-appear for units that actually recompile; compiler
  ERRORS always surface (an erroring unit has no valid DCU, so it always rebuilds).
