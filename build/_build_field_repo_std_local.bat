@echo off
REM Build the field repository editor, TDBGrid fallback build (no DevExpress needed), Win64.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0..\src\tools\field-repo"
if not exist "dcu-std" mkdir "dcu-std"
dcc64 -B -NUdcu-std -E. -U"..\..\sql" -NSSystem;Winapi;System.Win;Data;Vcl;FireDAC;Vcl.Imaging dl-field-repo-std.dpr
echo BUILD_EXITCODE=%errorlevel%
