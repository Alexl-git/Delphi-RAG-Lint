@echo off
setlocal
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
dcc64 -E"C:\Projects\Delphi-RAG-lint\tests\fixtures\" -U"C:\Projects\Delphi-RAG-lint\src\delphi-plugin" -U"C:\Program Files (x86)\Embarcadero\Studio\37.0\lib\win64\release" -LUdesignide "C:\Projects\Delphi-RAG-lint\tests\fixtures\T43_refactorform.dpr"
echo EXIT_CODE=%ERRORLEVEL%
endlocal
