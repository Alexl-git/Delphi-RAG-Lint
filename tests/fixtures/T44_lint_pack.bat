@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
"%EXE%" lint "%HERE%RuleTest.pas" > "%HERE%t44_out.txt" 2>&1
type "%HERE%t44_out.txt"
findstr /c:"goto-statement" "%HERE%t44_out.txt" >NUL || (echo FAIL: goto rule did not fire && exit /b 1)
findstr /c:"with-statement" "%HERE%t44_out.txt" >NUL || (echo FAIL: with rule did not fire && exit /b 1)
findstr /c:"empty-procedure-body" "%HERE%t44_out.txt" >NUL || (echo FAIL: empty-procedure-body rule did not fire && exit /b 1)
findstr /c:"large-magic-number" "%HERE%t44_out.txt" >NUL || (echo FAIL: large-magic-number rule did not fire && exit /b 1)
findstr /c:"string-equality-comparison" "%HERE%t44_out.txt" >NUL || (echo FAIL: string-equality-comparison rule did not fire && exit /b 1)
echo PASS
exit /b 0
