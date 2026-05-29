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

dcc64 -Q -B -E"%HERE%" -U"%SRC%" -LUdesignide "%HERE%T61_hovertracker.dpr" > "%HERE%t61_build.txt" 2>&1

if errorlevel 1 (
  echo FAIL: T61 compile failed
  type "%HERE%t61_build.txt"
  exit /b 1
)

echo PASS
exit /b 0
