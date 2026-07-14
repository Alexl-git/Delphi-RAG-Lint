@echo off
setlocal
set HERE=%~dp0
set ROOT=%HERE%..\..
set RSVARS=C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat

call "%RSVARS%" >NUL 2>&1
if errorlevel 1 (
  echo SKIP: rsvars.bat not found - Delphi not installed
  exit /b 0
)

set SRC=%ROOT%\src
set EXE=%HERE%T40_compile_parser.exe
set LOG=%HERE%t40_compile.log

rem CompileCheck now pulls in more units transitively (preprocess, etc.), so
rem search every src subdir for units + includes rather than an incomplete list.
set UU=-U"%SRC%\core" -U"%SRC%\diagnostics" -U"%SRC%\preprocess" -U"%SRC%\parser" -U"%SRC%\config" -U"%SRC%\storage"
set II=-I"%SRC%\core" -I"%SRC%\diagnostics" -I"%SRC%\preprocess" -I"%SRC%\parser"
dcc64 -Q -B %UU% %II% -E"%SRC%\..\tests\fixtures" "%HERE%T40_compile_parser.dpr" >"%LOG%" 2>&1

if errorlevel 1 (
  echo FAIL: T40 compile failed
  type "%LOG%"
  exit /b 1
)

"%EXE%"
if errorlevel 1 (
  echo FAIL: T40 runtime assertion failed
  exit /b 1
)

echo PASS
exit /b 0
