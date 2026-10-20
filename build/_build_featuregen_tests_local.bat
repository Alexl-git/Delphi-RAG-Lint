@echo off
REM Build the featuregen console test runner (Win64) from THIS checkout.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0..\src\tools\featuregen\tests"
REM Own dcu folder: the units are compiled under the tool's build too.
if not exist "dcu" mkdir "dcu"
dcc64 -B -NUdcu -NSSystem;Winapi;System.Win FeatureGenTests.dpr
echo BUILD_EXITCODE=%errorlevel%
