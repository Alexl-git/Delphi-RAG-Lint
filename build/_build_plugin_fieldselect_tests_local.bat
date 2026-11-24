@echo off
REM Build the field-selection tests of the IDE plugin (TT-DIALOG, Win64) from THIS checkout: the console runner of the
REM model and the form smoke test.
REM Usage: _build_plugin_fieldselect_tests_local.bat [outdir]
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0..\tests\plugin\fieldselect"
set OUT=%~1
if "%OUT%"=="" set OUT=.
if not exist "%OUT%\dcu" mkdir "%OUT%\dcu"
dcc64 -B -NU"%OUT%\dcu" -E"%OUT%" -NSSystem;Winapi;System.Win;Vcl FieldSelectTests.dpr
echo MODEL_EXITCODE=%errorlevel%
dcc64 -B -NU"%OUT%\dcu" -E"%OUT%" -NSSystem;Winapi;System.Win;Vcl FieldSelectForms.dpr
echo FORMS_EXITCODE=%errorlevel%
