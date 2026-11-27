@echo off
REM Build the command-model tests of Copy Grid Columns (GCP-P, Win64) from THIS checkout.
REM Usage: _build_plugin_gridcopy_tests_local.bat [outdir]
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0..\tests\plugin\gridcopy"
set OUT=%~1
if "%OUT%"=="" set OUT=.
if not exist "%OUT%\dcu" mkdir "%OUT%\dcu"
dcc64 -B -NU"%OUT%\dcu" -E"%OUT%" -NSSystem;Winapi;System.Win;Vcl GridCopyCmdTests.dpr
echo BUILD_EXITCODE=%errorlevel%
