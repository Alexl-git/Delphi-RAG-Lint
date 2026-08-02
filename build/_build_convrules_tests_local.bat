@echo off
REM Build the ConvRulesEditor console test runner (Win64) from THIS checkout.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0..\src\tools\convrules-editor\tests"
dcc64 -B -NSSystem;Vcl;Winapi;System.Win ConvRulesModelTests.dpr
echo BUILD_EXITCODE=%errorlevel%
