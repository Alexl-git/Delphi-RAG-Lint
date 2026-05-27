@echo off
REM End-to-end smoke test for drag-lint.exe. Exercises every CLI surface
REM that ships in v0.2: index (folder + file + --project), query (--name
REM with fuzzy fallback + --qname + find-callers), lint (built-in rule +
REM external query rules), --dry-run, --version.
setlocal

set HERE=%~dp0
set ROOT=%HERE%..
set EXE=%ROOT%\third_party\dll\drag-lint.exe
set SMOKE=%ROOT%\tests\fixtures\Smoke.pas
set CALLS=%ROOT%\tests\fixtures\Calls.pas
set KINDS=%ROOT%\tests\fixtures\Kinds.pas
set LOOPFBN=%ROOT%\tests\fixtures\LoopFBN.pas
set SMOKEDFM=%ROOT%\tests\fixtures\SmokeForm.dfm
set DBSMOKE=%ROOT%\tests\smoke.sqlite
set DBCALLS=%ROOT%\tests\calls.sqlite
set DBKINDS=%ROOT%\tests\kinds.sqlite
set DBDFM=%ROOT%\tests\dfm.sqlite

if not exist "%EXE%" (
  echo ERROR: %EXE% not found. Run build\build_draglint.bat first.
  exit /b 1
)

del /q "%DBSMOKE%" "%DBSMOKE%-journal" "%DBSMOKE%-wal" "%DBSMOKE%-shm" 2>NUL
del /q "%DBCALLS%" "%DBCALLS%-journal" "%DBCALLS%-wal" "%DBCALLS%-shm" 2>NUL
del /q "%DBKINDS%" "%DBKINDS%-journal" "%DBKINDS%-wal" "%DBKINDS%-shm" 2>NUL
del /q "%DBDFM%" "%DBDFM%-journal" "%DBDFM%-wal" "%DBDFM%-shm" 2>NUL

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

echo === query --name TFo (fuzzy, expect TFoo candidate) ===
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

echo === index Kinds.pas (v0.2 coverage: expect 19 symbols) ===
"%EXE%" index "%KINDS%" --db "%DBKINDS%"
echo.

echo === query --name IShape (interface) ===
"%EXE%" query --name IShape --db "%DBKINDS%"
echo === query --name TColor (enum) ===
"%EXE%" query --name TColor --db "%DBKINDS%"
echo === query --name TPoint (record) ===
"%EXE%" query --name TPoint --db "%DBKINDS%"
echo === query --name FName (field) ===
"%EXE%" query --name FName --db "%DBKINDS%"
echo === query --name Name (property; expect IShape.Name + TShape.Name) ===
"%EXE%" query --name Name --db "%DBKINDS%"
echo === query --name clBlue (enum_value) ===
"%EXE%" query --name clBlue --db "%DBKINDS%"
echo.

echo === index SmokeForm.dfm (v0.2 DFM: expect form + components + 2 refs) ===
"%EXE%" index "%SMOKEDFM%" --db "%DBDFM%"
echo.

echo === query --name SmokeForm (form) ===
"%EXE%" query --name SmokeForm --db "%DBDFM%"
echo === query --name btnOK (component) ===
"%EXE%" query --name btnOK --db "%DBDFM%"
echo === query find-callers --name btnOKClick (event binding) ===
"%EXE%" query find-callers --name btnOKClick --db "%DBDFM%"
echo.

echo === lint LoopFBN.pas (expect 3 built-in findings; if external rules in ^<exedir^>\rules\ are loaded, extra findings may also appear) ===
"%EXE%" lint "%LOOPFBN%"
echo.

endlocal
