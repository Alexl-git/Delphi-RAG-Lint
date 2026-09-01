@echo off
REM Build drag-lint.exe Win64 -> dll-win64/.
setlocal
set RSVARS="C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
call %RSVARS%
if errorlevel 1 exit /b 1

set HERE=%~dp0
set ROOT=%HERE%..

cd /D "%ROOT%\src\cli"
msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal drag-lint.dproj
if errorlevel 1 exit /b 1

REM Stage the tree-sitter companions NEXT TO THE LINKED EXE, not only next to the
REM staged copy. The .pas declarations import them implicitly, so the loader needs
REM them in the exe's own directory. Without this the freshly linked
REM src\cli\Win64\Debug\drag-lint.exe -- which 51 of the 79 suites under
REM tests\autotest resolve -- cannot start: the loader falls through to PATH,
REM finds the x86 copies in third_party\dll, and dies 0xC000007B
REM STATUS_INVALID_IMAGE_FORMAT. That is a bitness mismatch, NOT a missing-DLL
REM error (which would be 0xC0000135), which is why it never looked like a
REM staging problem.
REM
REM WHAT GUARDS THIS: nothing dedicated, by choice. Remove this copy and the first
REM suite run without an explicit -Exe dies at process start, before its first
REM check, across all 51 -- loud and immediate. A .bat-level guard would be a
REM second implementation of the copy below. tests\run_battery.ps1 and
REM tests\autotest\run_exe_freshness.ps1 do not close it either: the freshness
REM guard checks exe existence and mtime-vs-newest-source only -- it never looks
REM for tree-sitter DLLs beside the exe, so it could not catch a regression here.
copy /Y "%ROOT%\third_party\dll-win64\tree-sitter*.dll" "%ROOT%\src\cli\Win64\Debug\" >NUL
if errorlevel 1 (
  echo ERROR: failed to stage tree-sitter companions into %ROOT%\src\cli\Win64\Debug
  exit /b 1
)

REM Stage the RULE CATALOGUE beside both exes. rules\ is the only TRACKED copy;
REM <exe-dir>\rules is gitignored, and until now nothing produced it -- so a
REM fresh clone had no external rules at all, and an edit to rules\*.scm was
REM INERT until someone remembered to copy it by hand. That is not theoretical:
REM the bare-except anchor fix was edited, built, and measured against the OLD
REM rule, with the whole suite passing. The Release and Win32 copies were 35 and
REM 104 files behind when this was found.
REM
REM dll-win32 WAS in this list between 0fddcf2 and the Win32 retirement, because
REM the IDE plugin fell back to the engine beside its BPL and that engine had no
REM rules\, so it answered "0 finding(s)" for every file and the editor gutter
REM went blank for a session. The fallback itself is now GONE (owner ruling
REM 2026-08-26: the engine is 64-bit only), so there is no 32-bit engine left to
REM keep a catalogue for. Do not re-add it without re-adding the fallback.
REM
REM tests\run_battery.ps1 (register K41) hashes rules\ against both of these
REM and shouts on drift, so this copy and that check are a matched pair: the
REM build makes them right, the battery proves they stayed right.
for %%D in ("%ROOT%\src\cli\Win64\Debug" "%ROOT%\third_party\dll-win64") do (
  if not exist "%%~D\rules" mkdir "%%~D\rules"
  REM MIRROR, NOT COPY. copy /Y never DELETES, so a rule RETIRED from rules\
  REM survived beside the exe forever. Retiring hardcoded-absolute-path.scm for
  REM the B7 built-in exposed it: the stale .scm would have loaded ALONGSIDE the
  REM new built-in under the SAME rule id on the next deploy, restoring the very
  REM finding flood the rewrite removed. The battery K41 content check could not
  REM see it either -- it walks rules\ asking present-and-identical, which
  REM finds MISSING and DIFFERS but never ORPHAN. Both halves fixed 2026-08-31.
  if exist "%%~D\rules\*.scm"  del /Q "%%~D\rules\*.scm"
  if exist "%%~D\rules\*.json" del /Q "%%~D\rules\*.json"
  copy /Y "%ROOT%\rules\*.scm"  "%%~D\rules\" >NUL
  copy /Y "%ROOT%\rules\*.json" "%%~D\rules\" >NUL
  if exist "%ROOT%\rules\builtin-symbols.txt" copy /Y "%ROOT%\rules\builtin-symbols.txt" "%%~D\rules\" >NUL
)

REM STAGE THE ENGINE. The plain copy stays FIRST and is the ordinary path: when
REM nothing holds the target this is one copy and no PowerShell is launched.
REM
REM When it does fail, the cause is almost always a LOCK, and the old message
REM ("failed to stage <path>") named the FILE and not the HOLDER -- which is why
REM the real cause took several rebuild cycles to identify. A running process
REM holds an execute lock on its own image, and the Delphi plugin spawns
REM drag-lint.exe as a long-lived LSP child, so an IDE that is merely OPEN
REM blocks the deploy moments after the compile succeeded.
REM
REM stage-engine.ps1 names the holder, asks the plugin to hold off so it will
REM NOT respawn, stops it, and retries. Killing without the hold-off loses the
REM race -- both clients respawn the server within about a second.
copy /Y "%ROOT%\src\cli\Win64\Debug\drag-lint.exe" "%ROOT%\third_party\dll-win64\drag-lint.exe" >NUL
if errorlevel 1 (
  pwsh -NoProfile -File "%ROOT%\build\stage-engine.ps1" -FreshExe "%ROOT%\src\cli\Win64\Debug\drag-lint.exe" -Target "%ROOT%\third_party\dll-win64\drag-lint.exe"
  if errorlevel 1 (
    echo ERROR: failed to stage %ROOT%\third_party\dll-win64\drag-lint.exe
    exit /b 1
  )
)
echo OK: staged Win64 drag-lint.exe + tree-sitter companions
endlocal
