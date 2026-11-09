# build\ -- build scripts

All `.bat`/`.ps1` here are 7-bit ASCII, CRLF. Build the engine and plugin through the
`delphi-build` skill recipe (rsvars -> msbuild, output to a log).

## Where binaries go: the three-directory rule (`third_party\`)

| Directory | Holds | Written by |
|---|---|---|
| `dll-win64\` | x64 `tree-sitter.dll`, `tree-sitter-delphi13.dll`, `tree-sitter-dfm.dll` and the Win64 `drag-lint.exe` | every 64-bit build (`_buildgrammar.bat`, `_buildgrammar64_manual.bat`, `_builddfm64_manual.bat`, `_buildruntime64.bat`, `build_draglint_win64.bat` via `stage-engine.ps1`) |
| `dll-win32\` | x86 tree-sitter DLLs, the IDE BPL/DCP (`dclDragLintWizard.*`) | every 32-bit build (`_buildgrammar32*.bat`, `_builddfm32*.bat`, `_buildruntime32.bat`, `deploy-staged.bat`) |
| `dll\` | LEGACY. Tracked x86 tree-sitter DLLs that `deploy-staged.bat` (`DLL32`) copies into `dll-win32\`, plus an old BPL and `rules\` | nothing new. Never write an x64 DLL or an engine exe here (`tests\autotest\run_no_engine_beside_bpl.ps1`) |

Why: the 64-bit grammar bat used to default its output to `dll\`, overwriting the canonical
x86 copies with x64 ones and breaking the Win32 stage. A bare-name lookup that reaches `dll\`
or `dll-win32\` before `dll-win64\` loads the wrong bitness (0xC000007B), or a stale engine.

Readers of `dll\` (checked 2026-11-08): `deploy-staged.bat`, `build_draglint.bat` and
`build_phase0.bat` (legacy 64-bit bats that still point `OUT` at it), and the tracked files
themselves. `pack-lint-release.ps1`, `stage-engine.ps1`, `installer\` and the plugin/CLI
`.dproj` files do not read it.

## Grammar / runtime bats

`_buildgrammar.bat [grammar-checkout] [output-dll]` (x64, tree-sitter CLI),
`_buildgrammar32.bat` (x86 CLI), `_buildgrammar32_manual.bat` / `_buildgrammar64_manual.bat`
(`cl.exe` direct, the form that works when the CLI cannot find a compiler). Same two
parameters everywhere; the default output is `dll-win32\` for the 32 bats and `dll-win64\`
for the 64 bats. A worktree path works as the first parameter. Pass an explicit second
parameter to build to a scratch path without touching `third_party\`.

## Grammar gate tools

`tools\grammar\` holds the grammar lanes' instruments: `tsdiff` (tree-by-tree comparison of
two grammar DLLs over a file list), `tserr` (ERROR / MISSING counts and outermost-ERROR bytes,
old vs new) and `tsparse` (S-expression dump of one file), built by
`tools\grammar\build-grammar-tools.bat [grammar-checkout] [out-dir]` with the same `_vsenv.bat`
the manual grammar bats use; `tools\grammar\gate-grammar.ps1` runs generate + DLL build +
`tree-sitter test` + tsdiff/tserr for one grammar worktree against a base DLL pair. They read
DLLs only and never write `third_party\`. See `tools\grammar\README.md`.

## Staging a built engine

`stage-engine.ps1 -FreshExe <new> -Target <deployed>` holds the deployed engine, kills the
processes running the target IMAGE (by image path, never by name), copies, and retries; the
build bats and `pack-lint-release.ps1` stage through it. `build_draglint_win64.bat -NoStage`
builds without staging (lane/worktree builds). Never kill `drag-lint.exe` by name or
bare-copy over it; see `docs\wiki\ide-release.md`.
