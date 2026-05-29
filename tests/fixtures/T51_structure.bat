@echo off
setlocal
set HERE=%~dp0
cmd /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && dcc64 -E""%HERE%"" -U""%HERE%..\..\src\delphi-plugin"" ""%HERE%T51_structure.dpr""" 2>&1 | findstr /v "Found compiler" > "%HERE%t51_build.txt"
if not exist "%HERE%T51_structure.exe" (echo FAIL: build failed && type "%HERE%t51_build.txt" && exit /b 1)
"%HERE%T51_structure.exe" > "%HERE%t51_out.txt"
type "%HERE%t51_out.txt"
findstr /c:"OK" "%HERE%t51_out.txt" >NUL || (echo FAIL: T51 did not print OK && exit /b 1)
echo PASS
exit /b 0
