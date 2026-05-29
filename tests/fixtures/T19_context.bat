@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set DB=%HERE%t8.sqlite

"%EXE%" context --task "modify Docs.TDocDemo.GetBaz" --db "%DB%" > "%HERE%t19_out.txt" 2>&1
if errorlevel 1 (
  echo FAIL: context command failed
  type "%HERE%t19_out.txt"
  exit /b 1
)

type "%HERE%t19_out.txt"

findstr /c:"Token count" "%HERE%t19_out.txt" >/dev/null
if errorlevel 1 (
  echo FAIL: no token estimate
  exit /b 1
)

findstr /c:"GetBaz" "%HERE%t19_out.txt" >/dev/null
if errorlevel 1 (
  echo FAIL: target symbol missing
  exit /b 1
)

echo PASS
exit /b 0
