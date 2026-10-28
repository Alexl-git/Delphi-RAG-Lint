@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0"
if not exist dcu mkdir dcu
REM dl-project-setup.res is checked in (manifest asInvoker; regenerate with rc.exe from the .rc)
dcc32 -B -NUdcu -E. -NSSystem;Winapi;System.Win;Vcl;Vcl.Imaging dl-project-setup.dpr
echo BUILD_EXITCODE=%errorlevel%
