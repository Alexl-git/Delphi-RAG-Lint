@echo off
REM Build the field-repository schema-facts (FR-SCHEMA) test runner (Win64) from THIS checkout.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0..\tests\fieldrepo"
if not exist "dcu" mkdir "dcu"
dcc64 -B -NUdcu -E. -U"..\..\src\sql" -NSSystem;Winapi;System.Win;Data;FireDAC SchemaFactsTests.dpr
echo BUILD_EXITCODE=%errorlevel%
