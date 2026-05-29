@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set DB=%HERE%t14.sqlite
if not exist "%DB%" (
  "%EXE%" index "%HERE%Calls.pas" --db "%DB%" >NUL
)
"%EXE%" typeat %HERE%Calls.pas:17:8 --db "%DB%" > "%HERE%t22_out.txt"
type "%HERE%t22_out.txt"
findstr /c:"Compute" "%HERE%t22_out.txt" >NUL || (echo FAIL: Compute not resolved && exit /b 1)
echo PASS
exit /b 0
