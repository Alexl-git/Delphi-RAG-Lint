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

dcc64 -Q -B -E"%FIXTURES%" -U"%SRC%" -LUdesignide "%FIXTURES%\T58_symbolsearch_form.dpr" > "%FIXTURES%\t58_build.txt" 2>&1

if errorlevel 1 (
  echo FAIL: T58 compile failed
  type "%FIXTURES%\t58_build.txt"
  exit /b 1
)

"%FIXTURES%\T58_symbolsearch_form.exe"
if errorlevel 1 (
  echo FAIL: T58 runtime assertion failed
  exit /b 1
)

echo PASS
exit /b 0
