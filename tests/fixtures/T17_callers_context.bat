@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set DB=%HERE%t17.sqlite
del /q "%DB%" 2>NUL
"%EXE%" index "%HERE%Calls.pas" --db "%DB%" >NUL
"%EXE%" query find-callers --name Compute --context 2 --db "%DB%" > "%HERE%t17_out.txt"
type "%HERE%t17_out.txt"
findstr /c:"Compute" "%HERE%t17_out.txt" >NUL || (echo FAIL: no callers && exit /b 1)
findstr /c:" 16:" "%HERE%t17_out.txt" >NUL || (echo FAIL: no context lines && exit /b 1)
echo PASS
