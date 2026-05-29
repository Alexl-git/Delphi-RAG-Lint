@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set DB=%HERE%t14.sqlite
if not exist "%DB%" (
  "%EXE%" index "%HERE%Calls.pas" --db "%DB%" >NUL
)
"%EXE%" rename --qname Calls.TWidget.Compute --to Calc --db "%DB%" --dry-run > "%HERE%t35_out.txt"
type "%HERE%t35_out.txt"
findstr /c:"Compute -> Calc" "%HERE%t35_out.txt" >NUL || (echo FAIL: no edits in dry-run && exit /b 1)
echo PASS
exit /b 0
