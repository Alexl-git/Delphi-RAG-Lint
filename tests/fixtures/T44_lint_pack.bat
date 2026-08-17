@echo off
setlocal
set HERE=%~dp0
if not defined EXE set EXE=%HERE%..\..\third_party\dll-win64\drag-lint.exe
"%EXE%" lint "%HERE%RuleTest.pas" > "%HERE%t44_out.txt" 2>&1
type "%HERE%t44_out.txt"
findstr /c:"goto-statement" "%HERE%t44_out.txt" >NUL || (echo FAIL: goto rule did not fire && exit /b 1)
findstr /c:"with-statement" "%HERE%t44_out.txt" >NUL || (echo FAIL: with rule did not fire && exit /b 1)
findstr /c:"empty-procedure-body" "%HERE%t44_out.txt" >NUL || (echo FAIL: empty-procedure-body rule did not fire && exit /b 1)
findstr /c:"large-magic-number" "%HERE%t44_out.txt" >NUL || (echo FAIL: large-magic-number rule did not fire && exit /b 1)
REM string-equality-comparison: assertion REMOVED 2026-08-17, deliberately.
REM The rule still exists but is default_enabled=false -- it was narrowed and
REM switched off because it was over-eager, firing on ANY `=` binary expression
REM (the repo history says so in as many words). RuleTest.pas contains no string
REM comparison at all; its `B = True` / `B = False` lines are what the old,
REM over-eager form used to flag. So this assertion demanded a false positive.
REM Re-adding a string comparison to the fixture would re-assert a rule the
REM project deliberately defanged, so the assertion goes rather than the rule.
echo PASS
exit /b 0
