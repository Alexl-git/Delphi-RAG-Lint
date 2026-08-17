@echo off
REM Integration test for `drag-lint resolve-uses`: index a tiny 2-unit fixture,
REM then resolve a const defined in one unit and assert the defining unit, the
REM suggestion, and (with --in) the "already in uses" detection.
setlocal
set HERE=%~dp0
set ROOT=%HERE%..\..
if not defined EXE set EXE=%ROOT%\third_party\dll-win64\drag-lint.exe
set TMP=%HERE%ru_tmp
set DB=%HERE%ru.sqlite

rmdir /s /q "%TMP%" 2>NUL
mkdir "%TMP%"

> "%TMP%\ProviderUnit.pas" (
echo unit ProviderUnit;
echo interface
echo const
echo   MAGIC_CONST = 42;
echo type
echo   TWidget = class
echo   end;
echo implementation
echo end.
)

> "%TMP%\ConsumerUnit.pas" (
echo unit ConsumerUnit;
echo interface
echo uses ProviderUnit;
echo implementation
echo end.
)

del "%DB%" 2>NUL
"%EXE%" index "%TMP%" --db "%DB%" >NUL

echo === resolve-uses --name MAGIC_CONST ===
"%EXE%" resolve-uses --name MAGIC_CONST --db "%DB%" > "%HERE%ru_out.txt"
type "%HERE%ru_out.txt"
findstr /c:"ProviderUnit" "%HERE%ru_out.txt" >NUL || (echo FAIL: defining unit not found && exit /b 1)
findstr /c:"Suggestion" "%HERE%ru_out.txt" >NUL || (echo FAIL: no suggestion && exit /b 1)

echo === resolve-uses --name MAGIC_CONST --in ConsumerUnit (already uses ProviderUnit) ===
"%EXE%" resolve-uses --name MAGIC_CONST --in "%TMP%\ConsumerUnit.pas" --db "%DB%" > "%HERE%ru_in.txt"
type "%HERE%ru_in.txt"
findstr /c:"already in uses" "%HERE%ru_in.txt" >NUL || (echo FAIL: --in did not detect existing use && exit /b 1)

echo === resolve-uses --name DoesNotExist (exit code 1) ===
"%EXE%" resolve-uses --name ZZZ_NoSuchSymbol --db "%DB%" > "%HERE%ru_none.txt"
type "%HERE%ru_none.txt"
findstr /c:"No unit" "%HERE%ru_none.txt" >NUL || (echo FAIL: missing-symbol message && exit /b 1)

rmdir /s /q "%TMP%" 2>NUL
del "%DB%" "%HERE%ru_out.txt" "%HERE%ru_in.txt" "%HERE%ru_none.txt" 2>NUL
echo PASS
