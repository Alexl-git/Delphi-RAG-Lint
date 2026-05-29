@echo off
setlocal
set HERE=%~dp0
cmd /c "call ""C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"" && dcc64 -E""%HERE%"" -U""%HERE%..\..\src\delphi-plugin"" ""%HERE%T27_lsp_client.dpr""" 2>&1 | findstr /v "Found compiler" > "%HERE%t27_build.txt"
if not exist "%HERE%T27_lsp_client.exe" (echo FAIL: build failed && type "%HERE%t27_build.txt" && exit /b 1)
"%HERE%T27_lsp_client.exe" > "%HERE%t27_out.txt"
type "%HERE%t27_out.txt"
findstr /c:"OK" "%HERE%t27_out.txt" >NUL || (echo FAIL: client did not roundtrip && exit /b 1)
echo PASS
exit /b 0
