@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
pushd "%HERE%..\.."
type "%HERE%T23_mcp_typeat.json" | "%EXE%" serve > "%HERE%t23_out.txt"
popd
type "%HERE%t23_out.txt"
findstr /c:"get_type_at_position" "%HERE%t23_out.txt" >NUL || (echo FAIL: tool not advertised && exit /b 1)
findstr /c:"Compute" "%HERE%t23_out.txt" >NUL || (echo FAIL: Compute not resolved && exit /b 1)
echo PASS
exit /b 0
