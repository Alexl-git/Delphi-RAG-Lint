@echo off
setlocal
set HERE=%~dp0
REM Rewritten 2026-08-17. The original nested cmd /c "call ""...."" && dcc64 ..."
REM never reached the compiler (cmd resolved the doubled quotes to '""C:\Program'),
REM and -E"%HERE%" hit the Windows trap where a TRAILING BACKSLASH before a
REM closing quote escapes it, swallowing the next argument. %HERE% and the src
REM paths contain no spaces so they need no quotes; %IDELIB% does but has no
REM trailing backslash, so it is quoted whole. Do not "tidy" this.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" >NUL
dcc64 -E%HERE% -U%HERE%..\..\src\delphi-plugin %HERE%T51_structure.dpr > "%HERE%t51_build.txt" 2>&1
if not exist "%HERE%T51_structure.exe" (echo FAIL: build failed && type "%HERE%t51_build.txt" && exit /b 1)
"%HERE%T51_structure.exe" > "%HERE%t51_out.txt"
type "%HERE%t51_out.txt"
findstr /c:"OK" "%HERE%t51_out.txt" >NUL || (echo FAIL: T51 did not print OK && exit /b 1)
echo PASS
exit /b 0
