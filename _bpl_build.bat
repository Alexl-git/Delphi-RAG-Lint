@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:normal "C:\Projects\Delphi-RAG-lint\src\delphi-plugin\dclDragLintWizard.dproj"
