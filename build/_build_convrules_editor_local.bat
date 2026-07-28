@echo off
REM Build ConvRulesEditor.exe (Win64) from THIS checkout, then stage to dll-win64.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0..\src\tools\convrules-editor"
dcc64 -B ConvRulesEditor.dpr
echo BUILD_EXITCODE=%errorlevel%
if %errorlevel%==0 copy /Y ConvRulesEditor.exe "%~dp0..\third_party\dll-win64\ConvRulesEditor.exe" >NUL
