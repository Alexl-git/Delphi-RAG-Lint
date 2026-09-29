@echo off
setlocal
set HERE=%~dp0
set RSVARS=C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat
set ROOT=%HERE%..\..
set SRC=%ROOT%\src\delphi-plugin

call "%RSVARS%" >NUL 2>&1
if errorlevel 1 (
  echo SKIP: rsvars.bat not found - Delphi not installed
  exit /b 0
)

REM -E%HERE% UNQUOTED: %HERE% ends in '\', and a backslash before a closing quote
REM escapes it -- -E"%HERE%" swallowed every later argument, dcc64 got no project,
REM printed its usage and exited 0, so this fixture passed without compiling.
REM -DDRAGLINT_TEST_REGROOT: Settings then writes HKCU\...\DelphiPlugin.Test, never the owner's live key. -B so no stale DCU built without the define is reused.
dcc64 -DDRAGLINT_TEST_REGROOT -Q -B -E%HERE% -U"%SRC%" -U"%ROOT%\src\core" -U"%ROOT%\src\index" -U"%ROOT%\src\workspace" -U"%ROOT%\src\lint" -U"%ROOT%\src\project" -LUdesignide "%HERE%T61_hovertracker.dpr" > "%HERE%t61_build.txt" 2>&1

if errorlevel 1 (
  echo FAIL: T61 compile failed
  type "%HERE%t61_build.txt"
  exit /b 1
)

echo PASS
exit /b 0
