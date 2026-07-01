@echo off
setlocal
set HERE=%~dp0
set ROOT=%HERE%..\..
set LINT_SRC=%ROOT%\src\lint
set CORE_SRC=%ROOT%\src\core
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
dcc64 -E%HERE% -U%LINT_SRC% -U%CORE_SRC% %HERE%T65_profile_apply.dpr 2>&1 | findstr /v "Found compiler" > "%HERE%t65_build.txt"
if not exist "%HERE%T65_profile_apply.exe" (echo FAIL: build failed && type "%HERE%t65_build.txt" && exit /b 1)
"%HERE%T65_profile_apply.exe" > "%HERE%t65_out.txt"
type "%HERE%t65_out.txt"
findstr /c:"0 fail" "%HERE%t65_out.txt" >NUL || (echo FAIL: T65 reported failures && exit /b 1)
echo PASS
exit /b 0
