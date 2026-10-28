@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0"
if not exist ..\dcu_t mkdir ..\dcu_t
dcc32 -B -NU..\dcu_t -E. -NSSystem;Winapi;System.Win ProjectCtxTests.dpr
echo BUILD_EXITCODE=%errorlevel%
