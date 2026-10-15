@echo off
REM Build drag-lint-open.exe (Win64 Debug) -> third_party\dll-win64\.
REM
REM The draglint:// protocol handler: GUI subsystem, so a browser click never
REM flashes a console. RTL only. This script DEPLOYS (copies the exe into
REM third_party\dll-win64); for a build that stays in the tree, run msbuild on
REM src\tools\uri-handler\drag-lint-open.dproj directly.
setlocal
set RSVARS="C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
call %RSVARS%
if errorlevel 1 exit /b 1

set HERE=%~dp0
set ROOT=%HERE%..

cd /D "%ROOT%\src\tools\uri-handler"
msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal drag-lint-open.dproj
if errorlevel 1 exit /b 1

copy /Y "%ROOT%\src\tools\uri-handler\Win64\Debug\drag-lint-open.exe" "%ROOT%\third_party\dll-win64\drag-lint-open.exe" >NUL
if errorlevel 1 (
  echo ERROR: failed to stage %ROOT%\third_party\dll-win64\drag-lint-open.exe
  exit /b 1
)
echo OK: staged Win64 drag-lint-open.exe
endlocal
