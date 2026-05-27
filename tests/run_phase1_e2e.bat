@echo off
REM End-to-end Phase 1 test: index Smoke.pas, query symbols, verify expected output.
setlocal

set HERE=%~dp0
set ROOT=%HERE%..
set EXE=%ROOT%\third_party\dll\drag-lint.exe
set FIXTURE=%ROOT%\tests\fixtures\Smoke.pas
set DB=%ROOT%\tests\smoke.sqlite

if not exist "%EXE%" (
  echo ERROR: %EXE% not found. Run build\build_draglint.bat first.
  exit /b 1
)

del /q "%DB%" "%DB%-journal" "%DB%-wal" "%DB%-shm" 2>NUL

echo === drag-lint --version ===
"%EXE%" --version
echo.
echo === drag-lint index Smoke.pas ===
"%EXE%" index "%FIXTURE%" --db "%DB%"
echo.
echo === drag-lint query --name TFoo ===
"%EXE%" query --name TFoo --db "%DB%"
echo.
echo === drag-lint query --name DoBar ===
"%EXE%" query --name DoBar --db "%DB%"
echo.
echo === drag-lint query --qname Smoke.TFoo.GetBaz ===
"%EXE%" query --qname Smoke.TFoo.GetBaz --db "%DB%"
echo.
echo === drag-lint query --name DoesNotExist (expect 0 matches, exit 1) ===
"%EXE%" query --name DoesNotExist --db "%DB%"
endlocal
