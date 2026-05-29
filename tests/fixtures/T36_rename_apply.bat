@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
REM Use a COPY of Calls.pas so we don't corrupt the master fixture.
REM The copy still says "unit Calls;" inside, so the index produces
REM the qname Calls.TWidget.Compute - same as T35.
copy /Y "%HERE%Calls.pas" "%HERE%CallsRename.pas" >NUL
set DB=%HERE%t36.sqlite
del /q "%DB%" 2>NUL
"%EXE%" index "%HERE%CallsRename.pas" --db "%DB%" >NUL
"%EXE%" rename --qname Calls.TWidget.Compute --to Calc --db "%DB%" > "%HERE%t36_out.txt"
type "%HERE%t36_out.txt"
findstr /c:"function Calc" "%HERE%CallsRename.pas" >NUL || (echo FAIL: declaration not renamed && exit /b 1)
if not exist "%HERE%CallsRename.pas.bak" (echo FAIL: backup missing && exit /b 1)
del /q "%HERE%CallsRename.pas" "%HERE%CallsRename.pas.bak" "%HERE%t36.sqlite"
echo PASS
exit /b 0
