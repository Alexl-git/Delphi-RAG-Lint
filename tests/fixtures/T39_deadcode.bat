@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set DB=%HERE%t14.sqlite
if not exist "%DB%" (
  "%EXE%" index "%HERE%Calls.pas" --db "%DB%" >NUL
)
"%EXE%" find-deadcode --db "%DB%" > "%HERE%t39_out.txt"
type "%HERE%t39_out.txt"
findstr /c:"dead-code candidate" "%HERE%t39_out.txt" >NUL || (echo FAIL: no summary line && exit /b 1)
echo PASS
exit /b 0
