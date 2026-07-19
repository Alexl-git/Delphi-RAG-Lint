@echo off
REM Build the ConvRulesEditor console test runner (Win64) via dcc64.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "C:\Projects\Delphi-RAG-lint\src\tools\convrules-editor\tests"
dcc64 -B -NSSystem;Vcl;Winapi;System.Win ConvRulesModelTests.dpr
echo BUILD_EXITCODE=%errorlevel%
