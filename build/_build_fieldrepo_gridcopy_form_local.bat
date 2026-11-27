@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~1"
if not exist dcu mkdir dcu
dcc64 -B -Q -NUdcu -E. "-Uc:\Program Files (x86)\DevExpress\VCL\Library\RS37\Win64" -NSSystem;Winapi;System.Win;Data;FireDAC;Vcl GridCopyLoad.dpr
echo BUILD_EXITCODE=%errorlevel%
