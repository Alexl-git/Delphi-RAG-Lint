@echo off
REM ---------------------------------------------------------------------------
REM deploy-staged.bat -- copy the freshly built BPL + drag-lint.exe into the
REM IDE's load location (third_party\dll-win32). The BPL and the running LSP
REM exe are LOCKED while RAD Studio is open, so:
REM
REM   1. CLOSE RAD Studio.
REM   2. Run this .bat (double-click or from a prompt).
REM   3. Reopen RAD Studio -- it auto-loads the updated design package.
REM ---------------------------------------------------------------------------
set DST=C:\Projects\Delphi-RAG-lint\third_party\dll-win32

set GRAPH=C:\Projects\Delphi-RAG-Lint-Graph\bin\Win32\drag_lint_graph.exe

set DLL32=C:\Projects\Delphi-RAG-lint\third_party\dll

REM 2026-08-26: the drag-lint.exe copies are GONE from this script. It used to
REM stage a WIN32 engine into third_party\dll-win32\ and third_party\dll\, both
REM of which win bare-name resolution ahead of the Win64 engine. That is how the
REM IDE spent a session spawning drag-lint 0.41.0-alpha of 2026-06-10. The BPL
REM and DCP are still staged here -- they are the only 32-bit artifacts.
echo Copying BPL + DCP + graph viewer into %DST% ...
copy /Y "C:\TEMP1\bpl_staging\dclDragLintWizard.bpl" "%DST%\dclDragLintWizard.bpl"
copy /Y "C:\TEMP1\bpl_staging\dclDragLintWizard.dcp" "%DST%\dclDragLintWizard.dcp"
if exist "%GRAPH%" copy /Y "%GRAPH%" "%DST%\drag_lint_graph.exe"
if exist "%GRAPH%" copy /Y "%GRAPH%" "%DLL32%\drag_lint_graph.exe"

REM Guard: always refresh the x86 tree-sitter DLLs from the canonical Win32 source.
REM (They live in third_party\dll and must never be replaced with x64 copies.)
copy /Y "%DLL32%\tree-sitter.dll"          "%DST%\tree-sitter.dll"
copy /Y "%DLL32%\tree-sitter-delphi13.dll" "%DST%\tree-sitter-delphi13.dll"
copy /Y "%DLL32%\tree-sitter-dfm.dll"      "%DST%\tree-sitter-dfm.dll"

echo.
echo Done. Reopen RAD Studio.
pause
