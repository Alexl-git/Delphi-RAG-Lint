@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set DB=%HERE%t8.sqlite
"%EXE%" surface --qname Docs.TDocDemo --db "%DB%" > "%HERE%t15_out.txt"
type "%HERE%t15_out.txt"
findstr /c:"TDocDemo = class" "%HERE%t15_out.txt" >NUL || (echo FAIL: class decl missing && exit /b 1)
findstr /c:"function GetBaz" "%HERE%t15_out.txt" >NUL || (echo FAIL: method sig missing && exit /b 1)
findstr /c:"begin Result :=" "%HERE%t15_out.txt" >NUL && (echo FAIL: impl leaked into surface && exit /b 1)
echo PASS
exit /b 0
