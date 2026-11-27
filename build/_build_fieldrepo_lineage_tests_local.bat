@echo off
REM Build the field lineage model test runner (Win64, 1.56 lane LIN-1) from THIS checkout.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0..\tests\fieldrepo"
if not exist "dcu" mkdir "dcu"
dcc64 -B -NUdcu -E. -U"..\..\src\sql;..\..\src\storage;..\..\src\core" -NSSystem;Winapi;System.Win;Data;FireDAC LineageTests.dpr
echo BUILD_EXITCODE=%errorlevel%
