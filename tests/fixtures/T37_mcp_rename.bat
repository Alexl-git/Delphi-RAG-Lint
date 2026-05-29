@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
pushd "%HERE%..\.."
type "%HERE%T37_mcp_rename.json" | "%EXE%" serve > "%HERE%t37_out.txt"
popd
type "%HERE%t37_out.txt"
findstr /c:"rename_symbol" "%HERE%t37_out.txt" >NUL || (echo FAIL: tool not advertised && exit /b 1)
findstr /c:"edits" "%HERE%t37_out.txt" >NUL || (echo FAIL: no edits in response && exit /b 1)
echo PASS
exit /b 0
