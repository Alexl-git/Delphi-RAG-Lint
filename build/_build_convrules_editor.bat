@echo off
REM Build ConvRulesEditor.exe (Win64) via dcc64, then stage to dll-win64.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "C:\Projects\Delphi-RAG-lint\src\tools\convrules-editor"
REM VCL styles: dcc64 cannot compile a .rc (E2161), so build the .res first.
brcc32 ConvRulesEditorStyles.rc -foConvRulesEditorStyles.res
echo RC_EXITCODE=%errorlevel%
dcc64 -B ConvRulesEditor.dpr
echo BUILD_EXITCODE=%errorlevel%
if %errorlevel%==0 copy /Y ConvRulesEditor.exe "C:\Projects\Delphi-RAG-lint\third_party\dll-win64\ConvRulesEditor.exe" >NUL
