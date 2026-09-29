@echo off
setlocal
set HERE=%~dp0
set ROOT=%HERE%..\..
set LINT_SRC=%ROOT%\src\lint
set CORE_SRC=%ROOT%\src\core
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
REM -NU: DCUs go to a private folder, never beside the sources in src\ -- a stray
REM src\*.dcu is reused by any later build that searches that directory.
if not exist "%HERE%_dcu\T63_lint_config_roundtrip" mkdir "%HERE%_dcu\T63_lint_config_roundtrip"
dcc64 -NU"%HERE%_dcu\T63_lint_config_roundtrip" -E%HERE% -U%LINT_SRC% -U%CORE_SRC% %HERE%T63_lint_config_roundtrip.dpr 2>&1 | findstr /v "Found compiler" > "%HERE%t63_build.txt"
if not exist "%HERE%T63_lint_config_roundtrip.exe" (echo FAIL: build failed && type "%HERE%t63_build.txt" && exit /b 1)
"%HERE%T63_lint_config_roundtrip.exe" > "%HERE%t63_out.txt"
type "%HERE%t63_out.txt"
findstr /c:"0 fail" "%HERE%t63_out.txt" >NUL || (echo FAIL: T63 reported failures && exit /b 1)
echo PASS
exit /b 0
