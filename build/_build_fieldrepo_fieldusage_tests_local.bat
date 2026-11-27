@echo off
REM Build the field-usage (UI-M) test runner (Win64) from THIS checkout.
REM Usage: _build_fieldrepo_fieldusage_tests_local.bat [outdir]
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0..\tests\fieldrepo"
set OUT=%~1
if "%OUT%"=="" set OUT=.
if not exist "%OUT%\dcu" mkdir "%OUT%\dcu"
set S=..\..\src
dcc64 -B -NU"%OUT%\dcu" -E"%OUT%" -U"%S%\sql;%S%\core;%S%\storage" -NSSystem;Winapi;System.Win;Data;FireDAC FieldUsageTests.dpr
set RC=%errorlevel%
echo BUILD_EXITCODE=%RC%
