@echo off
REM End-to-end smoke test for drag-lint.exe. Exercises every CLI surface
REM that ships in v0.1: index, query --name (exact + fuzzy fallback),
REM query --qname, query find-callers, lint, --version.
setlocal

set HERE=%~dp0
set ROOT=%HERE%..
set EXE=%ROOT%\third_party\dll\drag-lint.exe
set SMOKE=%ROOT%\tests\fixtures\Smoke.pas
set CALLS=%ROOT%\tests\fixtures\Calls.pas
set LOOPFBN=%ROOT%\tests\fixtures\LoopFBN.pas
set DBSMOKE=%ROOT%\tests\smoke.sqlite
set DBCALLS=%ROOT%\tests\calls.sqlite

if not exist "%EXE%" (
  echo ERROR: %EXE% not found. Run build\build_draglint.bat first.
  exit /b 1
)

del /q "%DBSMOKE%" "%DBSMOKE%-journal" "%DBSMOKE%-wal" "%DBSMOKE%-shm" 2>NUL
del /q "%DBCALLS%" "%DBCALLS%-journal" "%DBCALLS%-wal" "%DBCALLS%-shm" 2>NUL

echo === drag-lint --version ===
"%EXE%" --version
echo.

echo === index Smoke.pas (expect 4 symbols, 0 refs) ===
"%EXE%" index "%SMOKE%" --db "%DBSMOKE%"
echo.

echo === query --name TFoo (expect 1 match) ===
"%EXE%" query --name TFoo --db "%DBSMOKE%"
echo.

echo === query --name DoBar (expect 1 match) ===
"%EXE%" query --name DoBar --db "%DBSMOKE%"
echo.

echo === query --qname Smoke.TFoo.GetBaz (expect 1 match) ===
"%EXE%" query --qname Smoke.TFoo.GetBaz --db "%DBSMOKE%"
echo.

echo === query --name TFo (fuzzy, expect "no exact match" + TFoo candidate) ===
"%EXE%" query --name TFo --db "%DBSMOKE%"
echo.

echo === query --name DoBer (fuzzy typo, expect DoBar candidate) ===
"%EXE%" query --name DoBer --db "%DBSMOKE%"
echo.

echo === query --name DoesNotExist (expect 0 matches, exit 1) ===
"%EXE%" query --name DoesNotExist --db "%DBSMOKE%"
echo.

echo === index Calls.pas (expect 4 symbols, 4 refs) ===
"%EXE%" index "%CALLS%" --db "%DBCALLS%"
echo.

echo === query find-callers --name Compute (expect 3 callers) ===
"%EXE%" query find-callers --name Compute --db "%DBCALLS%"
echo.

echo === query find-callers --name WriteLn (expect 1 caller) ===
"%EXE%" query find-callers --name WriteLn --db "%DBCALLS%"
echo.

echo === lint LoopFBN.pas (expect 3 findings, exit 1) ===
"%EXE%" lint "%LOOPFBN%"
echo.

endlocal
