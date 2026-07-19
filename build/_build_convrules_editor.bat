@echo off
REM Build ConvRulesEditor.exe (Win64) via dcc64, then stage to dll-win64.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "C:\Projects\Delphi-RAG-lint\src\tools\convrules-editor"
dcc64 -B ConvRulesEditor.dpr
echo BUILD_EXITCODE=%errorlevel%
if %errorlevel%==0 copy /Y ConvRulesEditor.exe "C:\Projects\Delphi-RAG-lint\third_party\dll-win64\ConvRulesEditor.exe" >NUL
