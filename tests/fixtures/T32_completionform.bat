@echo off
setlocal
set HERE=%~dp0
set IDELIB=C:\Program Files (x86)\Embarcadero\Studio\37.0\lib\win64\release
REM Rewritten 2026-08-17. The original nested cmd /c "call ""...."" && dcc64 ..."
REM never reached the compiler (cmd resolved the doubled quotes to '""C:\Program'),
REM and -E"%HERE%" hit the Windows trap where a TRAILING BACKSLASH before a
REM closing quote escapes it, swallowing the next argument. %HERE% and the src
REM paths contain no spaces so they need no quotes; %IDELIB% does but has no
REM trailing backslash, so it is quoted whole. Do not "tidy" this.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" >NUL
REM -NU: DCUs go to a private folder, never beside the sources in src\ -- a stray
REM src\*.dcu is reused by any later build that searches that directory.
if not exist "%HERE%_dcu\T32_completionform" mkdir "%HERE%_dcu\T32_completionform"
dcc64 -NU"%HERE%_dcu\T32_completionform" -E%HERE% -U%HERE%..\..\src\delphi-plugin;%HERE%..\..\src\core "-U%IDELIB%" -LUdesignide %HERE%T32_completionform.dpr > "%HERE%t32_build.txt" 2>&1
if not exist "%HERE%T32_completionform.exe" (echo FAIL: build failed && type "%HERE%t32_build.txt" && exit /b 1)
"%HERE%T32_completionform.exe" > "%HERE%t32_out.txt"
type "%HERE%t32_out.txt"
findstr /c:"OK" "%HERE%t32_out.txt" >NUL || (echo FAIL: completion form unit did not print OK && exit /b 1)
echo PASS
exit /b 0
