@echo off
setlocal
set HERE=%~dp0
if not defined EXE set EXE=%HERE%..\..\third_party\dll-win64\drag-lint.exe
type "%HERE%T12_lsp.json" | "%EXE%" lsp --db "%HERE%t8.sqlite" > "%HERE%t12_out.txt"
type "%HERE%t12_out.txt"
findstr /c:"Computes the baz" "%HERE%t12_out.txt" >NUL || (echo FAIL: enriched hover missing && exit /b 1)
findstr /c:"value" "%HERE%t12_out.txt" >NUL || (echo FAIL: param missing && exit /b 1)
echo PASS
