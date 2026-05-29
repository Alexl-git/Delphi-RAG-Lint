@echo off
setlocal
set HERE=%~dp0
cmd /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && dcc64 -E""%HERE%"" -U""%HERE%..\..\src\delphi-plugin"" ""%HERE%T34_save_setting.dpr""" 2>&1 | findstr /v "Found compiler" > "%HERE%t34_build.txt"
if not exist "%HERE%T34_save_setting.exe" (echo FAIL: build failed && type "%HERE%t34_build.txt" && exit /b 1)
"%HERE%T34_save_setting.exe" > "%HERE%t34_out.txt"
type "%HERE%t34_out.txt"
findstr /c:"OK" "%HERE%t34_out.txt" >NUL || (echo FAIL: AutoReindexOnSave did not roundtrip && exit /b 1)
echo PASS
exit /b 0
