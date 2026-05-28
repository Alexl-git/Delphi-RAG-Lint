@echo off
setlocal
set HERE=%~dp0
set ROOT=%HERE%..\..
set EXE=%ROOT%\third_party\dll\drag-lint.exe
set DB=%HERE%t8.sqlite
"%EXE%" hover --qname Docs.TDocDemo.GetBaz --db "%DB%" > "%HERE%t9_out.txt"
type "%HERE%t9_out.txt"
findstr /c:"Computes the baz" "%HERE%t9_out.txt" >NUL || (echo FAIL: summary missing && exit /b 1)
findstr /c:"value" "%HERE%t9_out.txt" >NUL || (echo FAIL: param missing && exit /b 1)
findstr /c:"Returns:" "%HERE%t9_out.txt" >NUL || (echo FAIL: returns label missing && exit /b 1)
echo PASS
