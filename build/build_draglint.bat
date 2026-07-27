@echo off
REM Build drag-lint.exe (Win64 console) via msbuild + Delphi 13.
setlocal

set RSVARS="C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if not exist %RSVARS% (
  echo ERROR: rsvars.bat not found at %RSVARS%
  exit /b 1
)

set HERE=%~dp0
set ROOT=%HERE%..
set OUT=%ROOT%\third_party\dll

if not exist "%OUT%\tree-sitter.dll"             ( echo ERROR: missing tree-sitter.dll & exit /b 1 )
if not exist "%OUT%\tree-sitter-delphi13.dll"    ( echo ERROR: missing tree-sitter-delphi13.dll & exit /b 1 )

call %RSVARS%
if errorlevel 1 exit /b 1

cd /D "%ROOT%\src\cli"
msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal drag-lint.dproj
if errorlevel 1 (
  echo BUILD FAILED.
  exit /b 1
)

REM Stage built exe next to the DLLs so it can find them
if exist "%ROOT%\src\cli\Win64\Debug\drag-lint.exe" (
  copy /Y "%ROOT%\src\cli\Win64\Debug\drag-lint.exe" "%OUT%\drag-lint.exe"
  REM goto here, not a nested if-errorlevel block, because of a real cmd.exe
  REM bug: exit /b does not reliably propagate two parenthesized blocks deep
  REM -- the outer if-exist block plus an inner if-errorlevel block --
  REM verified: the ERROR text prints but the process exit code comes back 0
  REM anyway. goto out of the block first, then exit /b at the top level,
  REM does not have that failure mode.
  REM Note for editors: no parentheses in this comment block on purpose --
  REM cmd.exe counts parens inside REM text too, even though it never
  REM executes it, so a stray one here would unbalance the enclosing block.
  if errorlevel 1 goto :stage_failed
  echo OK: staged %OUT%\drag-lint.exe
) else (
  echo ERROR: drag-lint.exe not produced
  exit /b 1
)
endlocal
exit /b 0

:stage_failed
echo ERROR: failed to stage %OUT%\drag-lint.exe
exit /b 1
