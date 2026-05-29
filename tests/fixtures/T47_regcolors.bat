@echo off
setlocal
set HERE=%~dp0
cmd /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && dcc64 -E""%HERE%"" -U""%HERE%..\..\src\delphi-plugin"" ""%HERE%T47_regcolors.dpr""" 2>&1 | findstr /v "Found compiler" > "%HERE%t47_build.txt"
if not exist "%HERE%T47_regcolors.exe" (echo FAIL: build failed && type "%HERE%t47_build.txt" && exit /b 1)
"%HERE%T47_regcolors.exe" > "%HERE%t47_out.txt"
type "%HERE%t47_out.txt"
findstr /c:"OK" "%HERE%t47_out.txt" >NUL || (echo FAIL: T47 did not print OK && exit /b 1)
echo PASS
exit /b 0
