@echo off
setlocal
set HERE=%~dp0
REM T66: IsOpenableSourcePath -- a pure unit (System.SysUtils only), so no
REM designide link is needed. Same quoting rules as T30 (see its comment).
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" >NUL
REM -NU: DCUs go to a private folder, never beside the sources in src\ -- a stray
REM src\*.dcu is reused by any later build that searches that directory.
if not exist "%HERE%_dcu\T66_open_source_path" mkdir "%HERE%_dcu\T66_open_source_path"
REM A failed compile leaves the previous exe in place; delete it so a stale exe
REM can never print OK, and fail on the compiler's own exit code.
del "%HERE%T66_open_source_path.exe" 2>NUL
dcc64 -NU"%HERE%_dcu\T66_open_source_path" -E%HERE% -U%HERE%..\..\src\delphi-plugin %HERE%T66_open_source_path.dpr > "%HERE%t66_build.txt" 2>&1
if errorlevel 1 (echo FAIL: build failed && type "%HERE%t66_build.txt" && exit /b 1)
if not exist "%HERE%T66_open_source_path.exe" (echo FAIL: build failed && type "%HERE%t66_build.txt" && exit /b 1)
"%HERE%T66_open_source_path.exe" > "%HERE%t66_out.txt"
type "%HERE%t66_out.txt"
findstr /x /c:"OK" "%HERE%t66_out.txt" >NUL || (echo FAIL: open-source path validation && exit /b 1)
echo PASS
exit /b 0
