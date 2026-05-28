@echo off
setlocal
set HERE=%~dp0
set ROOT=%HERE%..\..
set EXE=%ROOT%\third_party\dll\drag-lint.exe
set DB=%HERE%t8.sqlite

echo === find --doc-tag deprecated ===
"%EXE%" query find --doc-tag deprecated --db "%DB%" > "%HERE%t10_dep.txt"
type "%HERE%t10_dep.txt"
findstr /c:"OldProc" "%HERE%t10_dep.txt" >NUL || (echo FAIL: deprecated not found && exit /b 1)

echo === find --doc-contains baz ===
"%EXE%" query find --doc-contains baz --db "%DB%" > "%HERE%t10_baz.txt"
type "%HERE%t10_baz.txt"
findstr /c:"GetBaz" "%HERE%t10_baz.txt" >NUL || (echo FAIL: doc-contains miss && exit /b 1)

echo === find --no-docs --kind method ===
"%EXE%" query find --no-docs --kind method --db "%DB%" > "%HERE%t10_nodocs.txt"
type "%HERE%t10_nodocs.txt"

echo PASS
