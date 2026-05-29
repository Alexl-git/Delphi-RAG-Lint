@echo off
setlocal
set HERE=%~dp0
cmd /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && dcc64 -E""%HERE%"" -U""%HERE%..\..\src\delphi-plugin"" ""%HERE%T55_codelens_cache.dpr""" 2>&1 | findstr /v "Found compiler" > "%HERE%t55_build.txt"
if not exist "%HERE%T55_codelens_cache.exe" (echo FAIL: build failed && type "%HERE%t55_build.txt" && exit /b 1)
"%HERE%T55_codelens_cache.exe" > "%HERE%t55_out.txt"
type "%HERE%t55_out.txt"
findstr /c:"OK" "%HERE%t55_out.txt" >NUL || (echo FAIL: T55 did not print OK && exit /b 1)
echo PASS
exit /b 0
