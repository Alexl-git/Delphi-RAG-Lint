@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
python "%HERE%lsp_send.py" T25 "%HERE%t25_in.bin"
if errorlevel 1 (echo FAIL: lsp_send.py failed && exit /b 1)
type "%HERE%t25_in.bin" | "%EXE%" lsp --db "%HERE%t8.sqlite" > "%HERE%t25_out.txt"
type "%HERE%t25_out.txt"
findstr /c:"signatures" "%HERE%t25_out.txt" >NUL || (echo FAIL: signatureHelp response missing && exit /b 1)
echo PASS
exit /b 0
