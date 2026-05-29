@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
"%EXE%" lint "%HERE%BrokenSyntax.pas" > "%HERE%t53_out.txt" 2>&1
type "%HERE%t53_out.txt"
findstr /c:"parser-error" "%HERE%t53_out.txt" >NUL || (echo FAIL: parser-error rule did not fire && exit /b 1)
echo PASS
exit /b 0
