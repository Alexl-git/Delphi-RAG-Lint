@echo off
REM Build ConvRulesEditor.exe (Win64) from THIS checkout.
REM   (no argument)  build only: the exe stays in src\tools\convrules-editor\.
REM   stage          ALSO copy it to third_party\dll-win64\ -- the live folder the
REM                  engine's own release refreshes (pack-lint-release.ps1 passes it).
REM Staging used to be unconditional, so every developer or agent build silently
REM replaced the editor in dll-win64 (2026-10-05, job C6). The release pack does NOT
REM need the copy -- it ships src\tools\convrules-editor\ConvRulesEditor.exe.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0..\src\tools\convrules-editor"
REM VCL styles: dcc64 cannot compile a .rc (E2161), so build the .res first.
brcc32 ConvRulesEditorStyles.rc -foConvRulesEditorStyles.res
echo RC_EXITCODE=%errorlevel%
REM Gate on it: a broken .rc plus a stale .res would otherwise report BUILD_EXITCODE=0
REM while silently embedding the previous resource.
if %errorlevel% neq 0 exit /b %errorlevel%
REM DCUs go to .\dcu, not beside the source. dcc64 does NOT create the output
REM directory -- a missing one is a hard error (F1027), so make it first.
if not exist "dcu" mkdir "dcu"
dcc64 -B -NUdcu ConvRulesEditor.dpr
echo BUILD_EXITCODE=%errorlevel%
set BUILD_RC=%errorlevel%
if not %BUILD_RC%==0 exit /b %BUILD_RC%
if /I "%~1"=="stage" (
  copy /Y ConvRulesEditor.exe "%~dp0..\third_party\dll-win64\ConvRulesEditor.exe" >NUL
  echo STAGED=third_party\dll-win64\ConvRulesEditor.exe
)
exit /b 0
