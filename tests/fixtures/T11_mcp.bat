@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
type "%HERE%T11_mcp.json" | "%EXE%" serve > "%HERE%t11_out.txt"
type "%HERE%t11_out.txt"
findstr /c:"get_symbol_doc" "%HERE%t11_out.txt" >NUL || (echo FAIL: tool not advertised && exit /b 1)
findstr /c:"Computes the baz" "%HERE%t11_out.txt" >NUL || (echo FAIL: doc not returned && exit /b 1)
findstr /c:"OldProc" "%HERE%t11_out.txt" >NUL || (echo FAIL: deprecated not returned && exit /b 1)
echo PASS
