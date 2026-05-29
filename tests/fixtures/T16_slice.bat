@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set DB=%HERE%t8.sqlite
"%EXE%" slice --qname Docs.TDocDemo --db "%DB%" > "%HERE%t16_out.txt"
type "%HERE%t16_out.txt"
findstr /c:"unit Docs" "%HERE%t16_out.txt" >NUL || (echo FAIL: unit header missing && exit /b 1)
findstr /c:"TDocDemo = class" "%HERE%t16_out.txt" >NUL || (echo FAIL: class decl missing && exit /b 1)
findstr /c:"function TDocDemo.GetBaz" "%HERE%t16_out.txt" >NUL || (echo FAIL: impl method missing && exit /b 1)
echo PASS
