@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
pushd "%HERE%..\.."
type "%HERE%T18_mcp_v017.json" | "%EXE%" serve > "%HERE%t18_out.txt"
popd
type "%HERE%t18_out.txt"
findstr /c:"get_impact" "%HERE%t18_out.txt" >NUL || (echo FAIL: get_impact not advertised && exit /b 1)
findstr /c:"get_surface" "%HERE%t18_out.txt" >NUL || (echo FAIL: get_surface not advertised && exit /b 1)
findstr /c:"get_slice" "%HERE%t18_out.txt" >NUL || (echo FAIL: get_slice not advertised && exit /b 1)
findstr /c:"TDocDemo" "%HERE%t18_out.txt" >NUL || (echo FAIL: response missing TDocDemo && exit /b 1)
echo PASS
