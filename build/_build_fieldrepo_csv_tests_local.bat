@echo off
REM Build the TTCSV (CSV -> FDMemTable) console test runner (Win64) from THIS checkout.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0..\tests\fieldrepo"
if not exist "dcu" mkdir "dcu"
dcc64 -B -NUdcu -NSSystem;Data;Winapi CsvMemTableTests.dpr
echo BUILD_EXITCODE=%errorlevel%
