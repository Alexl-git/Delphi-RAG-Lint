@echo off
setlocal
set HERE=%~dp0
cmd /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && dcc64 -E""%HERE%"" -U""%HERE%..\..\src\delphi-plugin"" ""%HERE%T29_settings.dpr""" 2>&1 | findstr /v "Found compiler" > "%HERE%t29_build.txt"
if not exist "%HERE%T29_settings.exe" (echo FAIL: build failed && type "%HERE%t29_build.txt" && exit /b 1)
"%HERE%T29_settings.exe" > "%HERE%t29_out.txt"
type "%HERE%t29_out.txt"
findstr /c:"OK" "%HERE%t29_out.txt" >NUL || (echo FAIL: settings did not roundtrip && exit /b 1)
echo PASS
exit /b 0
