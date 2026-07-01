@echo off
rem Build the design-time plugin BPL for the RAD Studio IDE.
rem The IDE on this machine is 32-bit (bds.exe in Program Files (x86)) and loads
rem the Win32 package registered at third_party\dll-win32\dclDragLintWizard.bpl.
rem Therefore build Win32 (NOT Win64) -- the Base group sends the BPL/DCP straight
rem to third_party\dll-win32, the IDE's actual load path. RAD Studio must be CLOSED
rem (it locks the loaded BPL). A Win64 build (dll-win64) is useless to a 32-bit IDE.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /d "%~dp0"
msbuild /t:Build /p:Config=Debug /p:Platform=Win32 dclDragLintWizard.dproj
