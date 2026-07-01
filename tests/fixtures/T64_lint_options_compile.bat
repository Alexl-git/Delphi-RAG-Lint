@echo off
setlocal
set HERE=%~dp0
set ROOT=%HERE%..\..
set PLUGIN_SRC=%ROOT%\src\delphi-plugin
set LINT_SRC=%ROOT%\src\lint
set CORE_SRC=%ROOT%\src\core
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
set IDELIB=%BDS%\lib\win64\release
if exist "%HERE%T64_lint_options_compile.exe" del "%HERE%T64_lint_options_compile.exe"
dcc64 -E%HERE% -U%PLUGIN_SRC% -U%LINT_SRC% -U%CORE_SRC% "-U%IDELIB%" -LUdesignide %HERE%T64_lint_options_compile.dpr 2>&1 | findstr /v "Found compiler" > "%HERE%t64_build.txt"
if not exist "%HERE%T64_lint_options_compile.exe" (echo FAIL: build failed && type "%HERE%t64_build.txt" && exit /b 1)
"%HERE%T64_lint_options_compile.exe" > "%HERE%t64_out.txt"
type "%HERE%t64_out.txt"
findstr /c:"OK" "%HERE%t64_out.txt" >NUL || (echo FAIL: T64 did not print OK && exit /b 1)
echo PASS
exit /b 0
