@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set SRC=%HERE%UsageDemo.pas
set DBD=%HERE%t44_deep.sqlite
set DBS=%HERE%t44_shallow.sqlite
del "%DBD%" "%DBS%" 2>NUL

rem shallow: no usage refs -> usages finds nothing
"%EXE%" index "%SRC%" --db "%DBS%" --shallow >NUL
"%EXE%" usages --name dxDBGrid1 --db "%DBS%" | findstr /c:"reads: 0" >NUL || (echo FAIL: shallow should have 0 reads && exit /b 1)

rem deep: usage refs -> usages finds the reads + the declaration
"%EXE%" index "%SRC%" --db "%DBD%" --deep >NUL
"%EXE%" usages --name dxDBGrid1 --db "%DBD%" > "%HERE%t44_out.txt"
type "%HERE%t44_out.txt"
findstr /c:"declarations: 1" "%HERE%t44_out.txt" >NUL || (echo FAIL: deep should find the declaration && exit /b 1)
findstr /c:"reads: 4" "%HERE%t44_out.txt" >NUL || (echo FAIL: deep should find 4 reads && exit /b 1)

rem json shape
"%EXE%" usages --name dxDBGrid1 --db "%DBD%" --format json | findstr /c:"\"reads\":" >NUL || (echo FAIL: json reads key && exit /b 1)
echo PASS
exit /b 0
