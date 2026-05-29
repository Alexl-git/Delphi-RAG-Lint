@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set DB=%HERE%t8.sqlite

"%EXE%" bench-context --db "%DB%" --n 3 > "%HERE%t20_out.txt" 2>&1
if errorlevel 1 (
  echo FAIL: bench-context command failed
  type "%HERE%t20_out.txt"
  exit /b 1
)

type "%HERE%t20_out.txt"

findstr /c:"Reduction" "%HERE%t20_out.txt" >/dev/null
if errorlevel 1 (
  echo FAIL: no reduction line
  exit /b 1
)

echo PASS
exit /b 0
