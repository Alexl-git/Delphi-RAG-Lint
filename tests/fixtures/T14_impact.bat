@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set DB=%HERE%t14.sqlite
del /q "%DB%" 2>NUL
"%EXE%" index "%HERE%Calls.pas" --db "%DB%" >NUL
"%EXE%" impact --qname Calls.TWidget.Compute --db "%DB%" --depth 2 > "%HERE%t14_out.txt"
type "%HERE%t14_out.txt"
findstr /c:"Depth 1:" "%HERE%t14_out.txt" >NUL || (echo FAIL: no depth 1 output && exit /b 1)
echo PASS
