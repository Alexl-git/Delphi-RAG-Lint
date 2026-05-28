@echo off
setlocal
set EXE=%~dp0..\..\third_party\dll\drag-lint.exe
set DB=%~dp0..\t1.sqlite
del /q "%DB%" 2>NUL
"%EXE%" index "%~dp0Smoke.pas" --db "%DB%"
python "%~dp0check_schema.py" "%DB%" > "%~dp0t1_actual.txt"
findstr /c:"symbol_docs" "%~dp0t1_actual.txt" >NUL || (echo FAIL: symbol_docs table missing && exit /b 1)
echo PASS
