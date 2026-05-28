@echo off
setlocal
set HERE=%~dp0
set ROOT=%HERE%..\..
set EXE=%ROOT%\third_party\dll\drag-lint.exe
set DB=%HERE%t8.sqlite
del /q "%DB%" 2>NUL
"%EXE%" index "%HERE%Docs.pas" --db "%DB%"
python -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); rows=list(c.execute('SELECT s.qualified_name, d.format, d.summary FROM symbols s JOIN symbol_docs d ON d.symbol_id = s.id ORDER BY s.qualified_name')); [print((r[0] or '')+'|'+(r[1] or '')+'|'+(r[2] or '')) for r in rows]" "%DB%" > "%HERE%t8_out.txt"
type "%HERE%t8_out.txt"
findstr /c:"Docs.TDocDemo.GetBaz|xmldoc|Computes the baz" "%HERE%t8_out.txt" >NUL || (echo FAIL: GetBaz doc not stored && exit /b 1)
findstr /c:"Docs.TDocDemo.Add|pasdoc|Adds two numbers." "%HERE%t8_out.txt" >NUL || (echo FAIL: Add PasDoc not stored && exit /b 1)
findstr /c:"Docs.TDocDemo.DoOne|oneline|One-liner doc above this method" "%HERE%t8_out.txt" >NUL || (echo FAIL: DoOne oneliner not stored && exit /b 1)
echo PASS
