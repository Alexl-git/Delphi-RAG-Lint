@echo off
setlocal
set HERE=%~dp0
cmd /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && dcc64 -E""%HERE%"" -U""%HERE%..\..\src\delphi-plugin"" ""%HERE%T48_diag_cache.dpr""" 2>&1 | findstr /v "Found compiler" > "%HERE%t48_build.txt"
if not exist "%HERE%T48_diag_cache.exe" (echo FAIL: build failed && type "%HERE%t48_build.txt" && exit /b 1)
"%HERE%T48_diag_cache.exe" > "%HERE%t48_out.txt"
type "%HERE%t48_out.txt"
findstr /c:"OK" "%HERE%t48_out.txt" >NUL || (echo FAIL: T48 did not print OK && exit /b 1)
echo PASS
exit /b 0
