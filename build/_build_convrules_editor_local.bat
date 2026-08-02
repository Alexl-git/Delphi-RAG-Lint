@echo off
REM Build ConvRulesEditor.exe (Win64) from THIS checkout, then stage to dll-win64.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0..\src\tools\convrules-editor"
REM VCL styles: dcc64 cannot compile a .rc (E2161), so build the .res first.
brcc32 ConvRulesEditorStyles.rc -foConvRulesEditorStyles.res
echo RC_EXITCODE=%errorlevel%
REM Gate on it: a broken .rc plus a stale .res would otherwise report BUILD_EXITCODE=0
REM while silently embedding the previous resource.
if %errorlevel% neq 0 exit /b %errorlevel%
dcc64 -B ConvRulesEditor.dpr
echo BUILD_EXITCODE=%errorlevel%
if %errorlevel%==0 copy /Y ConvRulesEditor.exe "%~dp0..\third_party\dll-win64\ConvRulesEditor.exe" >NUL
