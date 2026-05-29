@echo off
setlocal
set HERE=%~dp0
cmd /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && dcc64 -E""%HERE%"" -U""%HERE%..\..\src\delphi-plugin"" ""%HERE%T54_settings_scan_libraries.dpr""" 2>&1 | findstr /v "Found compiler" > "%HERE%t54_build.txt"
if not exist "%HERE%T54_settings_scan_libraries.exe" (echo FAIL: build failed && type "%HERE%t54_build.txt" && exit /b 1)
"%HERE%T54_settings_scan_libraries.exe" > "%HERE%t54_out.txt"
type "%HERE%t54_out.txt"
findstr /c:"OK" "%HERE%t54_out.txt" >NUL || (echo FAIL: ScanLibraries did not roundtrip && exit /b 1)
echo PASS
exit /b 0
