@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe

"%EXE%" lint "%HERE%RuleTest.pas" > "%HERE%t62_out.txt" 2>&1
type "%HERE%t62_out.txt"

findstr /c:"boolean-comparison-true" "%HERE%t62_out.txt" >NUL || (echo FAIL: boolean-comparison-true did not fire && exit /b 1)
findstr /c:"redundant-as-tobject" "%HERE%t62_out.txt" >NUL || (echo FAIL: redundant-as-tobject did not fire && exit /b 1)
findstr /c:"inherited-bare" "%HERE%t62_out.txt" >NUL || (echo FAIL: inherited-bare did not fire && exit /b 1)
echo PASS
exit /b 0
