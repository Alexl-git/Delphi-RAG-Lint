@echo off
REM Build drag-lint-switch.exe (Win64 Debug) -> third_party\dll-win64\.
REM
REM Win64 on purpose, like every other drag-lint process except the design-time
REM BPL: the BPL has no choice (the IDE is 32-bit), everything else is decoupled
REM over pipes and stays 64-bit so index size and RAM are never the constraint.
setlocal
set RSVARS="C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
call %RSVARS%
if errorlevel 1 exit /b 1

set HERE=%~dp0
set ROOT=%HERE%..

cd /D "%ROOT%\src\tools\lsp-switch"
msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal drag-lint-switch.dproj
if errorlevel 1 exit /b 1

copy /Y "%ROOT%\src\tools\lsp-switch\Win64\Debug\drag-lint-switch.exe" "%ROOT%\third_party\dll-win64\drag-lint-switch.exe" >NUL
if errorlevel 1 (
  echo ERROR: failed to stage %ROOT%\third_party\dll-win64\drag-lint-switch.exe
  exit /b 1
)
echo OK: staged Win64 drag-lint-switch.exe
endlocal
