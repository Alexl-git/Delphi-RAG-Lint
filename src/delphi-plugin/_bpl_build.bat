@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /d "%~dp0"
msbuild /t:Build /p:Config=Debug /p:Platform=Win64 dclDragLintWizard.dproj
