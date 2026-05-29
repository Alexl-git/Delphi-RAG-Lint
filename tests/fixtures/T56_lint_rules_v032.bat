@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe

"%EXE%" lint "%HERE%RuleTest.pas" > "%HERE%t56_out.txt" 2>&1
type "%HERE%t56_out.txt"

findstr /c:"compiler-magic-comments" "%HERE%t56_out.txt" >NUL || (echo FAIL: compiler-magic-comments did not fire && exit /b 1)
findstr /c:"nested-with" "%HERE%t56_out.txt" >NUL || (echo FAIL: nested-with did not fire && exit /b 1)
findstr /c:"assert-call" "%HERE%t56_out.txt" >NUL || (echo FAIL: assert-call did not fire && exit /b 1)
findstr /c:"case-magic-numbers" "%HERE%t56_out.txt" >NUL || (echo FAIL: case-magic-numbers did not fire && exit /b 1)
echo PASS
exit /b 0
