@echo off
setlocal
set HERE=%~dp0
if not defined EXE set EXE=%HERE%..\..\third_party\dll-win64\drag-lint.exe
set DB=%HERE%t37.sqlite
del /q "%DB%" "%DB%-wal" "%DB%-shm" 2>NUL
"%EXE%" index "%HERE%Calls.pas" --db "%DB%" >NUL
pushd "%HERE%..\.."
type "%HERE%T37_mcp_rename.json" | "%EXE%" serve > "%HERE%t37_out.txt"
popd
type "%HERE%t37_out.txt"
findstr /c:"rename_symbol" "%HERE%t37_out.txt" >NUL || (echo FAIL: tool not advertised && exit /b 1)
findstr /c:"edits" "%HERE%t37_out.txt" >NUL || (echo FAIL: no edits in response && exit /b 1)
echo PASS
exit /b 0
