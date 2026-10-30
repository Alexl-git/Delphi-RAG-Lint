@echo off
setlocal
set HERE=%~dp0
if not defined EXE set EXE=%HERE%..\..\third_party\dll-win64\drag-lint.exe
REM The frames come from lsp_send.py so the URI names THIS checkout (L#30).
python "%HERE%lsp_send.py" T12 "%HERE%t12_in.bin"
if errorlevel 1 (echo FAIL: lsp_send.py failed && exit /b 1)
type "%HERE%t12_in.bin" | "%EXE%" lsp --db "%HERE%t8.sqlite" > "%HERE%t12_out.txt"
type "%HERE%t12_out.txt"
findstr /c:"Computes the baz" "%HERE%t12_out.txt" >NUL || (echo FAIL: enriched hover missing && exit /b 1)
findstr /c:"value" "%HERE%t12_out.txt" >NUL || (echo FAIL: param missing && exit /b 1)
echo PASS
