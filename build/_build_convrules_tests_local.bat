@echo off
REM Build the ConvRulesEditor console test runner (Win64) from THIS checkout.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0..\src\tools\convrules-editor\tests"
REM DCUs go to .\dcu (its OWN folder, not the editor's -- the same units are
REM compiled here under a different -NS namespace set, and sharing one output
REM directory would make each build invalidate the other's DCUs).
if not exist "dcu" mkdir "dcu"
dcc64 -B -NUdcu -NSSystem;Vcl;Winapi;System.Win ConvRulesModelTests.dpr
echo BUILD_EXITCODE=%errorlevel%
