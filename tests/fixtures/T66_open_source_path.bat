@echo off
setlocal
set HERE=%~dp0
REM T66: IsOpenableSourcePath -- a pure unit (System.SysUtils only), so no
REM designide link is needed. Same quoting rules as T30 (see its comment).
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" >NUL
dcc64 -E%HERE% -U%HERE%..\..\src\delphi-plugin %HERE%T66_open_source_path.dpr > "%HERE%t66_build.txt" 2>&1
if not exist "%HERE%T66_open_source_path.exe" (echo FAIL: build failed && type "%HERE%t66_build.txt" && exit /b 1)
"%HERE%T66_open_source_path.exe" > "%HERE%t66_out.txt"
type "%HERE%t66_out.txt"
findstr /x /c:"OK" "%HERE%t66_out.txt" >NUL || (echo FAIL: open-source path validation && exit /b 1)
echo PASS
exit /b 0
