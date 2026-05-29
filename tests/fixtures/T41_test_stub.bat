@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set DB=%HERE%t14.sqlite
if not exist "%DB%" (
  "%EXE%" index "%HERE%Calls.pas" --db "%DB%" >NUL
)
"%EXE%" generate-test --qname Calls.TWidget.Compute --db "%DB%" > "%HERE%t41_out.txt"
type "%HERE%t41_out.txt"
findstr /c:"[TestFixture]" "%HERE%t41_out.txt" >NUL || (echo FAIL: DUnitX scaffold missing && exit /b 1)
findstr /c:"[Test]" "%HERE%t41_out.txt" >NUL || (echo FAIL: Test attribute missing && exit /b 1)
echo PASS
exit /b 0
