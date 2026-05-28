@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set DB=%HERE%t13.sqlite
del /q "%DB%" 2>NUL
cd /d "%HERE%T13_config"
"%EXE%" index "sample.pas" --db "%DB%"
python -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); [print('|'.join([str(x) if x is not None else '' for x in row])) for row in c.execute(\"SELECT s.name, COALESCE(d.format,''), COALESCE(d.summary,'') FROM symbols s LEFT JOIN symbol_docs d ON d.symbol_id = s.id WHERE s.name IN ('A','B') ORDER BY s.name\")]" "%DB%" > "%HERE%t13_out.txt"
type "%HERE%t13_out.txt"
findstr /c:"A|loose|loose preceding doc" "%HERE%t13_out.txt" >NUL || (echo FAIL: A loose not captured && exit /b 1)
findstr /r /c:"B||" "%HERE%t13_out.txt" >NUL && (echo OK: B has no doc) || (echo FAIL: B should have no doc with gap=0 && exit /b 1)
echo PASS
