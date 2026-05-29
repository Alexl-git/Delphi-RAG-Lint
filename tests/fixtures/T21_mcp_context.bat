@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
pushd "%HERE%..\.."
type "%HERE%T21_mcp_context.json" | "%EXE%" serve > "%HERE%t21_out.txt"
popd
type "%HERE%t21_out.txt"
findstr /c:"get_context_bundle" "%HERE%t21_out.txt" >NUL || (echo FAIL: get_context_bundle not advertised && exit /b 1)
findstr /c:"token_estimate" "%HERE%t21_out.txt" >NUL || (echo FAIL: no token_estimate in response && exit /b 1)
echo PASS
