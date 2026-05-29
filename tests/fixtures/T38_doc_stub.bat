@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set DB=%HERE%t14.sqlite
if not exist "%DB%" (
  "%EXE%" index "%HERE%Calls.pas" --db "%DB%" >NUL
)
"%EXE%" generate-docs --qname Calls.TWidget.Compute --db "%DB%" > "%HERE%t38_out.txt"
type "%HERE%t38_out.txt"
findstr /c:"<summary>" "%HERE%t38_out.txt" >NUL || (echo FAIL: xmldoc summary missing && exit /b 1)
findstr /c:"<returns>" "%HERE%t38_out.txt" >NUL || (echo FAIL: returns missing && exit /b 1)

"%EXE%" generate-docs --qname Calls.TWidget.Compute --format pasdoc --db "%DB%" > "%HERE%t38b_out.txt"
type "%HERE%t38b_out.txt"
findstr /c:"@returns" "%HERE%t38b_out.txt" >NUL || (echo FAIL: pasdoc @returns missing && exit /b 1)
echo PASS
exit /b 0
