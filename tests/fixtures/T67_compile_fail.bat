@echo off
setlocal
set HERE=%~dp0
REM POSITIVE CONTROL for the compile guard in tests\run_legacy_cli_fixtures.ps1.
REM T67_compile_fail.dpr does not compile. This .bat mirrors the shape of the
REM compiled fixtures (dcc64 into a build log, `if not exist <exe>`, run the
REM exe) and first PLANTS a stale exe -- a copy of hostname.exe -- the way an
REM earlier successful build would have left one. So the .bat runs the stale
REM exe and exits 0: judged by its exit code it PASSES. The runner must report
REM it as "compile failed" from the build log instead. Do not "fix" either.
copy /Y "%SystemRoot%\System32\hostname.exe" "%HERE%T67_compile_fail.exe" >NUL
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" >NUL
dcc64 -E%HERE% %HERE%T67_compile_fail.dpr > "%HERE%t67_build.txt" 2>&1
if not exist "%HERE%T67_compile_fail.exe" (echo FAIL: build failed && type "%HERE%t67_build.txt" && exit /b 1)
"%HERE%T67_compile_fail.exe" > "%HERE%t67_out.txt"
del "%HERE%T67_compile_fail.exe"
echo PASS
exit /b 0
