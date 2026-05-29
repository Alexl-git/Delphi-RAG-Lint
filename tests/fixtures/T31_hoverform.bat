@echo off
setlocal
set HERE=%~dp0
set IDELIB=C:\Program Files (x86)\Embarcadero\Studio\37.0\lib\win64\release
cmd /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && dcc64 -E""%HERE%"" -U""%HERE%..\..\src\delphi-plugin"" -U""%IDELIB%"" -LUdesignide ""%HERE%T31_hoverform.dpr""" 2>&1 | findstr /v "Found compiler" > "%HERE%t31_build.txt"
if not exist "%HERE%T31_hoverform.exe" (echo FAIL: build failed && type "%HERE%t31_build.txt" && exit /b 1)
"%HERE%T31_hoverform.exe" > "%HERE%t31_out.txt"
type "%HERE%t31_out.txt"
findstr /c:"OK" "%HERE%t31_out.txt" >NUL || (echo FAIL: hover form unit did not print OK && exit /b 1)
echo PASS
exit /b 0
