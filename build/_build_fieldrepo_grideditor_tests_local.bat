@echo off
REM Build the grid-column-editor write (1.56 GC-W) test runner (Win64) from THIS checkout.
REM Usage: _build_fieldrepo_grideditor_tests_local.bat [outdir]
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0..\tests\fieldrepo"
set OUT=%~1
if "%OUT%"=="" set OUT=.
if not exist "%OUT%\dcu" mkdir "%OUT%\dcu"
set S=..\..\src
dcc64 -B -NU"%OUT%\dcu" -E"%OUT%" -U"%S%\sql" -NSSystem;Winapi;System.Win;Data;FireDAC GridEditorWriteTests.dpr
set RC=%errorlevel%
echo BUILD_EXITCODE=%RC%
