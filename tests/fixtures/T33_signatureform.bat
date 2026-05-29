@echo off
setlocal
set HERE=%~dp0
set IDELIB=C:\Program Files (x86)\Embarcadero\Studio\37.0\lib\win64\release
cmd /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && dcc64 -E""%HERE%"" -U""%HERE%..\..\src\delphi-plugin"" -U""%IDELIB%"" -LUdesignide ""%HERE%T33_signatureform.dpr""" 2>&1 | findstr /v "Found compiler" > "%HERE%t33_build.txt"
if not exist "%HERE%T33_signatureform.exe" (echo FAIL: build failed && type "%HERE%t33_build.txt" && exit /b 1)
"%HERE%T33_signatureform.exe" > "%HERE%t33_out.txt"
type "%HERE%t33_out.txt"
findstr /c:"OK" "%HERE%t33_out.txt" >NUL || (echo FAIL: signature form unit did not print OK && exit /b 1)
echo PASS
exit /b 0
