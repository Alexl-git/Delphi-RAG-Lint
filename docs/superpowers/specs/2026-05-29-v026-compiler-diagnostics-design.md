# v0.26 — Compiler Diagnostics Integration

**Date:** 2026-05-29
**Status:** Design approved
**Branch:** `v0.26-compiler-diag` off `main`

## 1. Goal

Wire **every** `dcc32`/`dcc64` H/W/E/F message into our LSP so the plugin can
replace the IDE's Error Insight. The user's stated motivation: full
compiler diagnostics in one place, accurate (real compiler output),
visible in any LSP-aware editor.

## 2. The pipeline already exists

We have most of this built:

- v0.8 `drag-lint import-log <log-file>` parses dcc32/dcc64 H/W/E/F lines and inserts into the `compiler_findings` table
- v0.16+ severity mapping (Error/Warning/Info/Hint → LSP severities 1/2/3/4)
- v0.20 LSP `publishDiagnostics` notification
- v0.20 LSP `BuildDiagnostics(linter, file)` builds the LSP array from our linter

What's missing: connecting the dots. v0.26 ships three modes.

## 3. Modes

### 3.1 Manual log import (lowest risk)

User invokes `Tools → drag-lint → Import Build Log...` in the plugin:
- Browse to a saved msbuild/dcc output file, OR paste from clipboard
- drag-lint parses, inserts into compiler_findings, pushes per-file diagnostics via publishDiagnostics
- All Messages-pane / Problems-panel views update with the compiler's view

### 3.2 Auto-spawn on demand

Plugin Tools menu entry `Compile & Diagnose`:
- Spawns `msbuild <projfile.dproj> /v:normal /t:Build` in background
- Captures stdout/stderr
- Parses for H/W/E/F lines
- Pushes diagnostics per file
- Status shown in IDE Messages pane

### 3.3 Auto-spawn after save (opt-in)

Settings toggle `EnableCompilerOnSave` (default OFF — too noisy and slow for many projects):
- When ON: after `IOTAModuleNotifier.AfterSave`, spawn the compile-check in background
- Debounce: skip if another compile-check is in flight or one ran within the last 30 seconds

## 4. CLI surface

### `drag-lint compile-check <project-or-file> [--msbuild PATH] [--db PATH] [--format json|text]`

1. If target is a `.dproj`: spawn `msbuild <dproj> /v:normal /t:Build /nologo` synchronously
2. If target is a `.pas`: spawn `dcc64 -Q -B "<pas>" 2>&1` (best effort; missing deps are surfaced as errors)
3. Parse stdout+stderr line-by-line via the v0.8 regex (`^.+?\(\d+\)\s+(Hint|Warning|Error|Fatal):\s+(H|W|E|F)\d+\s+(.*)$`)
4. INSERT each finding into `compiler_findings`
5. Output: count of findings by severity in text mode; full array in json mode

Exit codes: 0 success, 1 some compiler errors, 2 spawn failed, 3 db error.

## 5. LSP integration

In `DRagLint.LSP.Server.pas`:
- Extend `BuildDiagnostics(linter, file)` to also UNION findings from `compiler_findings` table for the same file
- The same `textDocument/didOpen` and `textDocument/didSave` handlers now publish a combined diagnostic set

### 5.1 New LSP method (optional, defer to v0.27): `workspace/executeCommand "drag-lint.compileCheck"`

Lets editors trigger the compile-check from a command palette.

## 6. MCP tool

`run_compile_check`:
```json
{
  "target": "path/to/file.pas or project.dproj",
  "msbuild_path": "...optional...",
  "db": "..."
}
```

Returns:
```json
{
  "findings": [
    {"file": "...", "line": 12, "col": 5, "severity": "Warning", "code": "W1002", "message": "..."},
    ...
  ],
  "by_severity": {"errors": 0, "warnings": 5, "hints": 12},
  "exit_code": 0
}
```

## 7. Plugin (IDE)

Three new Tools menu entries:
- `Tools → drag-lint → Compile & Diagnose` — spawn msbuild against the active project, capture, push
- `Tools → drag-lint → Import Build Log...` — browse to log file, parse, push
- `Tools → drag-lint → Clear Compiler Findings` — wipe `compiler_findings` for the project

Settings additions:
- `MsbuildPath: string` (default: detect via `rsvars.bat` + `%FrameworkDir%`)
- `EnableCompilerOnSave: Boolean` (default OFF)
- `CompilerVerbosity: string` (default `'normal'`; can be `'minimal'`/`'detailed'`)

## 8. Refactor preview form (carried from v0.25)

Build `DragLint.Plugin.RefactorForm.pas` (the v0.25 F1 that got deferred):
- VCL form with qname + new-name fields
- Preview button: shell out to `drag-lint rename --dry-run`, capture stdout, show in TMemo
- Apply button: shell out to `drag-lint rename`, show count, refresh Messages pane

## 9. Storage helpers (new)

```pascal
function FindCompilerFindingsForFile(AFileId: Int64): TArray<TCompilerFinding>;
procedure ClearCompilerFindings(const AProjectPath: string);
```

`TCompilerFinding` already exists from v0.8.

## 10. Schema impact

None. The `compiler_findings` table already ships in v0.8 (schema version 3).

## 11. Stop criteria

### Auto-verifiable

1. `drag-lint compile-check tests/fixtures/Calls.pas` runs dcc64 and produces output (even if Calls.pas standalone gives errors due to missing deps, the parser ingests them correctly).
2. T40 ingests a hand-crafted dcc output file via `drag-lint import-log` (re-asserts existing v0.8 behavior).
3. MCP `run_compile_check` returns valid JSON.
4. LSP `textDocument/didSave` after a `compile-check` includes the compiler findings in the next `publishDiagnostics`.

### Manual

5. In RAD Studio, `Tools → drag-lint → Compile & Diagnose` runs msbuild and the Messages pane shows the findings.
6. Plugin → Settings → enable `EnableCompilerOnSave` → save a file → compile-check runs silently → diagnostics appear.

## 12. Out of scope (carried to v0.27+)

- Real-time syntax check (would need a tokenizer-only mode, not full dcc compile)
- Code-Insight-style "completions while typing" (already in v0.20 LSP completion; doesn't intersect compiler)
- macOS compiler (dcc-osx) — Win64 only
- Dependency-aware incremental builds
- Error Insight live underlines as you type (waits on full editor-buffer didChange)

## 13. Push cadence

Spec → push. F1 (manual log import + storage helper) → push. F2 (compile-check CLI + MCP) → push. F3 (LSP integration + plugin menu entries) → push. F4 (refactor preview form) → push. Tag + GitHub release after all four.
