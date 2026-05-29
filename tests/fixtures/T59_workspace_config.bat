@echo off
setlocal
set HERE=%~dp0
set ROOT=%HERE%..\..
set WORKSPACE_SRC=%ROOT%\src\workspace
cmd /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && dcc64 -E""%HERE%"" -U""%WORKSPACE_SRC%"" ""%HERE%T59_workspace_config.dpr""" 2>&1 | findstr /v "Found compiler" > "%HERE%t59_build.txt"
if not exist "%HERE%T59_workspace_config.exe" (echo FAIL: build failed && type "%HERE%t59_build.txt" && exit /b 1)
"%HERE%T59_workspace_config.exe" > "%HERE%t59_out.txt"
type "%HERE%t59_out.txt"
findstr /c:"OK" "%HERE%t59_out.txt" >NUL || (echo FAIL: T59 did not print OK && exit /b 1)
echo PASS
exit /b 0
