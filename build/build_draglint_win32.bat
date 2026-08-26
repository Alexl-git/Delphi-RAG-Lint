@echo off
REM ---------------------------------------------------------------------------
REM build_draglint_win32.bat -- RETIRED 2026-08-26. It no longer builds anything.
REM
REM Owner ruling 2026-08-26: only the 64-bit engine is needed, because it can
REM hold the large databases and indexes. The IDE BPL is the only 32-bit
REM artifact, because bds.exe is.
REM
REM This script used to stage a Win32 drag-lint.exe into third_party\dll-win32\
REM AND third_party\dll\. Both directories are consulted ahead of -- or instead
REM of -- the Win64 engine by anything resolving a bare exe name. A Win32 engine
REM in either one is how "Rebuild Index for This Project" came to run
REM drag-lint 0.41.0-alpha of 2026-06-10 and report
REM   FATAL: Exception: Unknown argument: --platform
REM against a flag the CLI had accepted for months.
REM
REM Kept as a refusal rather than deleted, so that running it TELLS you instead
REM of silently re-arming the trap.
REM
REM Build the engine with: build\build_draglint_win64.bat
REM ---------------------------------------------------------------------------
echo.
echo build_draglint_win32.bat is RETIRED -- there is no 32-bit drag-lint engine.
echo.
echo Use build\build_draglint_win64.bat instead.
echo.
echo Reason: a Win32 engine staged into third_party\dll-win32\ or third_party\dll\
echo is resolved ahead of the Win64 build by bare-name lookup, and then answers
echo with a months-old binary. See the header of this file.
echo.
exit /b 1
