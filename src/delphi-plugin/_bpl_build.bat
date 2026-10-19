@echo off
rem Build the design-time plugin BPL for the RAD Studio IDE.
rem Usage: _bpl_build.bat [Win32|Win64]   (default Win32)
rem The IDE loads the package for its own bitness: the Win32 BPL/DCP go to
rem third_party\dll-win32 and the Win64 BPL/DCP to third_party\dll-win64 (the
rem Base group sets the output paths). Release 1.31.5 shipped BOTH; build each
rem platform you deploy. RAD Studio must be CLOSED (it locks the loaded BPL).
set PLAT=%1
if "%PLAT%"=="" set PLAT=Win32
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /d "%~dp0"
msbuild /t:Build /p:Config=Debug /p:Platform=%PLAT% dclDragLintWizard.dproj
