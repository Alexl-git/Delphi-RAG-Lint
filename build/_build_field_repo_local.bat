@echo off
REM Build the field repository editor, DevExpress grid build (the DEFAULT shipped build), Win64.
REM DevExpress DCU folder: env DL_DEVEX_LIB (default: the RS37 Win64 folder under env DXVCL).
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if "%DXVCL%"=="" set "DXVCL=C:\Program Files (x86)\DevExpress\VCL"
if "%DL_DEVEX_LIB%"=="" set "DL_DEVEX_LIB=%DXVCL%\Library\RS37\Win64"
echo DL_DEVEX_LIB=%DL_DEVEX_LIB%
cd /D "%~dp0..\src\tools\field-repo"
if not exist "dcu-devex" mkdir "dcu-devex"
dcc64 -B -DDL_DEVEX -NUdcu-devex -E. -U"..\..\sql;%DL_DEVEX_LIB%" -R"%DL_DEVEX_LIB%" -NSSystem;Winapi;System.Win;Data;Vcl;FireDAC;Vcl.Imaging dl-field-repo.dpr
echo BUILD_EXITCODE=%errorlevel%
