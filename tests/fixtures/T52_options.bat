@echo off
setlocal
set HERE=%~dp0
set IDELIB=C:\Program Files (x86)\Embarcadero\Studio\37.0\lib\win64\release
cmd /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && dcc64 -E""%HERE%"" -U""%HERE%..\..\src\delphi-plugin"" -U""%IDELIB%"" -LUdesignide ""%HERE%T52_options.dpr""" 2>&1 | findstr /v "Found compiler" > "%HERE%t52_build.txt"
if not exist "%HERE%T52_options.exe" (echo FAIL: build failed && type "%HERE%t52_build.txt" && exit /b 1)
"%HERE%T52_options.exe" > "%HERE%t52_out.txt"
type "%HERE%t52_out.txt"
findstr /c:"OK" "%HERE%t52_out.txt" >NUL || (echo FAIL: T52 did not print OK && exit /b 1)
echo PASS
exit /b 0
