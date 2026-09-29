@echo off
setlocal
set HERE=%~dp0
set RSVARS=C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat
set ROOT=%HERE%..\..
set SRC=%ROOT%\src\delphi-plugin
set FIXTURES=%HERE:~0,-1%

call "%RSVARS%" >NUL 2>&1
if errorlevel 1 (
  echo SKIP: rsvars.bat not found - Delphi not installed
  exit /b 0
)

REM -NU: DCUs go to a private folder, never beside the sources in src\ -- a stray
REM src\*.dcu is reused by any later build that searches that directory.
if not exist "%HERE%_dcu\T43_refactorform" mkdir "%HERE%_dcu\T43_refactorform"
dcc64 -NU"%HERE%_dcu\T43_refactorform" -Q -B -E"%FIXTURES%" -U"%SRC%" -LUdesignide "%FIXTURES%\T43_refactorform.dpr" > "%FIXTURES%\t43_build.txt" 2>&1

if errorlevel 1 (
  echo FAIL: T43 compile failed
  type "%FIXTURES%\t43_build.txt"
  exit /b 1
)

"%FIXTURES%\T43_refactorform.exe"
if errorlevel 1 (
  echo FAIL: T43 runtime assertion failed
  exit /b 1
)

echo PASS
exit /b 0
