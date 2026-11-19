@echo off
REM Build the field-repository ORM / DataService generator tests (lane TTGEN) (Win64) from THIS checkout.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
REM src\core: DRagLint.FieldRepo.OrmGen reads its input through DRagLint.Core.Encoding (GHTRIAGE #16, 1.52).
cd /D "%~dp0..\tests\fieldrepo"
if not exist "dcu" mkdir "dcu"
dcc64 -B -NUdcu -E. -U"..\..\src\sql;..\..\src\core" -NSSystem;Winapi;System.Win;Data;FireDAC OrmGenTests.dpr
echo BUILD_EXITCODE=%errorlevel%