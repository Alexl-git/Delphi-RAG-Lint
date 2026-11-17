@echo off
REM Build the FieldRepo.ParamArray console test runner (Win64) from THIS checkout.
REM %1 = output dir (default %TEMP%\drag-lint-paramarray-tests); exe and dcu go there.
set OUTDIR=%~1
if "%OUTDIR%"=="" set OUTDIR=%TEMP%\drag-lint-paramarray-tests
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0..\tests\fieldrepo"
if not exist "%OUTDIR%\dcu" mkdir "%OUTDIR%\dcu"
dcc64 -B -NU"%OUTDIR%\dcu" -E"%OUTDIR%" -NSSystem;Winapi;System.Win ParamArrayTests.dpr
echo BUILD_EXITCODE=%errorlevel%
