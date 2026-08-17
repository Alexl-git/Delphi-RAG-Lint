@echo off
setlocal
set HERE=%~dp0
set RSVARS=C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat
set ROOT=%HERE%..\..
REM src\core joins the path because the plugin forms use DRagLint.Core.Model /
REM DRagLint.Hover.Contrast, which live there rather than beside them. The
REM dependency was added after this fixture was written and, the fixture being
REM invisible to the battery, nothing ever reported the resulting F2613.
set SRC=%ROOT%\src\delphi-plugin;%ROOT%\src\core;%ROOT%\src\index;%ROOT%\src\storage;%ROOT%\src\parser;%ROOT%\src\analysis;%ROOT%\src\config;%ROOT%\src\context;%ROOT%\src\diagnostics;%ROOT%\src\doc;%ROOT%\src\forms;%ROOT%\src\lint;%ROOT%\src\lsp;%ROOT%\src\output;%ROOT%\src\preprocess;%ROOT%\src\project;%ROOT%\src\query;%ROOT%\src\refactor;%ROOT%\src\report;%ROOT%\src\resolver;%ROOT%\src\sql;%ROOT%\src\workspace
set FIXTURES=%HERE:~0,-1%

call "%RSVARS%" >NUL 2>&1
if errorlevel 1 (
  echo SKIP: rsvars.bat not found - Delphi not installed
  exit /b 0
)

dcc64 -Q -B -E"%FIXTURES%" -U"%SRC%" -LUdesignide "%FIXTURES%\T57_usages_form.dpr" > "%FIXTURES%\t57_build.txt" 2>&1

if errorlevel 1 (
  echo FAIL: T57 compile failed
  type "%FIXTURES%\t57_build.txt"
  exit /b 1
)

"%FIXTURES%\T57_usages_form.exe"
if errorlevel 1 (
  echo FAIL: T57 runtime assertion failed
  exit /b 1
)

echo PASS
exit /b 0
