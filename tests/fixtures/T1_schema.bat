@echo off
setlocal
set EXE=%~dp0..\..\third_party\dll\drag-lint.exe
set DB=%~dp0..\t1.sqlite
del /q "%DB%" 2>NUL
"%EXE%" index "%~dp0Smoke.pas" --db "%DB%"
python -c "import sqlite3,sys; r=sqlite3.connect(sys.argv[1]).execute(\"SELECT 1 FROM sqlite_master WHERE type='table' AND name='symbol_docs'\").fetchone(); sys.exit(0 if r else 1)" "%DB%" || (echo FAIL: symbol_docs table missing && exit /b 1)
echo PASS
