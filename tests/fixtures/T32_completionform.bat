@echo off
setlocal
set HERE=%~dp0
set IDELIB=C:\Program Files (x86)\Embarcadero\Studio\37.0\lib\win64\release
cmd /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && dcc64 -E""%HERE%"" -U""%HERE%..\..\src\delphi-plugin"" -U""%IDELIB%"" -LUdesignide ""%HERE%T32_completionform.dpr""" 2>&1 | findstr /v "Found compiler" > "%HERE%t32_build.txt"
if not exist "%HERE%T32_completionform.exe" (echo FAIL: build failed && type "%HERE%t32_build.txt" && exit /b 1)
"%HERE%T32_completionform.exe" > "%HERE%t32_out.txt"
type "%HERE%t32_out.txt"
findstr /c:"OK" "%HERE%t32_out.txt" >NUL || (echo FAIL: completion form unit did not print OK && exit /b 1)
echo PASS
exit /b 0
