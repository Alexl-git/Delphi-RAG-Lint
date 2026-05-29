@echo off
setlocal
set HERE=%~dp0
set IDELIB=C:\Program Files (x86)\Embarcadero\Studio\37.0\lib\win64\release
cmd /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && dcc64 -E""%HERE%"" -U""%HERE%..\..\src\delphi-plugin"" -U""%IDELIB%"" -LUdesignide ""%HERE%T28_notifier.dpr""" 2>&1 | findstr /v "Found compiler" > "%HERE%t28_build.txt"
if not exist "%HERE%T28_notifier.exe" (echo FAIL: build failed && type "%HERE%t28_build.txt" && exit /b 1)
"%HERE%T28_notifier.exe" > "%HERE%t28_out.txt"
type "%HERE%t28_out.txt"
findstr /c:"OK" "%HERE%t28_out.txt" >NUL || (echo FAIL: notifier unit did not print OK && exit /b 1)
echo PASS
exit /b 0
