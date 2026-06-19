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
set EXE=C:\Projects\Delphi-RAG-lint\src\cli\Win32\Release\drag-lint.exe

set GRAPH=C:\Projects\Delphi-RAG-Lint-Graph\bin\Win32\drag_lint_graph.exe

echo Copying BPL + DCP + exe + graph viewer into %DST% ...
copy /Y "C:\TEMP1\bpl_staging\dclDragLintWizard.bpl" "%DST%\dclDragLintWizard.bpl"
copy /Y "C:\TEMP1\bpl_staging\dclDragLintWizard.dcp" "%DST%\dclDragLintWizard.dcp"
copy /Y "%EXE%" "%DST%\drag-lint.exe"
copy /Y "%EXE%" "C:\Projects\Delphi-RAG-lint\third_party\dll\drag-lint.exe"
if exist "%GRAPH%" copy /Y "%GRAPH%" "%DST%\drag_lint_graph.exe"
if exist "%GRAPH%" copy /Y "%GRAPH%" "C:\Projects\Delphi-RAG-lint\third_party\dll\drag_lint_graph.exe"

echo.
echo Done. Reopen RAD Studio.
pause
