@echo off
setlocal
set HERE=%~dp0
REM T68: ParseDragLintUri -- a pure unit over the plugin's pure path gate
REM (IsOpenableSourcePath, T66), so no designide link is needed. Same quoting
REM rules as T30 (see its comment).
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" >NUL
REM -NU: DCUs go to a private folder, never beside the sources in src\ -- a stray
REM src\*.dcu is reused by any later build that searches that directory.
if not exist "%HERE%_dcu\T68_draglint_uri" mkdir "%HERE%_dcu\T68_draglint_uri"
dcc64 -NU"%HERE%_dcu\T68_draglint_uri" -E%HERE% -U%HERE%..\..\src\core;%HERE%..\..\src\delphi-plugin %HERE%T68_draglint_uri.dpr > "%HERE%t68_build.txt" 2>&1
if not exist "%HERE%T68_draglint_uri.exe" (echo FAIL: build failed && type "%HERE%t68_build.txt" && exit /b 1)
"%HERE%T68_draglint_uri.exe" > "%HERE%t68_out.txt"
type "%HERE%t68_out.txt"
findstr /x /c:"OK" "%HERE%t68_out.txt" >NUL || (echo FAIL: draglint uri validation && exit /b 1)
echo PASS
exit /b 0
