@echo off
REM Build featuregen.exe (Win64) from THIS checkout.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0..\src\tools\featuregen"
if not exist "dcu" mkdir "dcu"
dcc64 -B -NUdcu -NSSystem;Winapi;System.Win featuregen.dpr
echo BUILD_EXITCODE=%errorlevel%