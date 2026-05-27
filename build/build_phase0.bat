@echo off
REM Build the Phase 0 smoke test (Win64 console) via msbuild + Delphi 13.
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

cd /D "%HERE%"
call %RSVARS%
if errorlevel 1 exit /b 1

msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal Phase0Smoke.dproj
if errorlevel 1 (
  echo BUILD FAILED.
  exit /b 1
)

REM Stage built exe next to the DLLs so it can find them
if exist "%HERE%Win64\Debug\phase0_smoke.exe" (
  copy /Y "%HERE%Win64\Debug\phase0_smoke.exe" "%OUT%\phase0_smoke.exe" >NUL
  echo OK: built and staged %OUT%\phase0_smoke.exe
) else (
  echo ERROR: phase0_smoke.exe not produced
  exit /b 1
)
endlocal
