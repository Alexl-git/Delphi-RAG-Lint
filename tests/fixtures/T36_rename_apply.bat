@echo off
setlocal
set HERE=%~dp0
if not defined EXE set EXE=%HERE%..\..\third_party\dll-win64\drag-lint.exe
REM Use a COPY of Calls.pas so we don't corrupt the master fixture.
REM The copy still says "unit Calls;" inside, so the index produces
REM the qname Calls.TWidget.Compute - same as T35.
copy /Y "%HERE%Calls.pas" "%HERE%CallsRename.pas" >NUL
set DB=%HERE%t36.sqlite
del /q "%DB%" 2>NUL
"%EXE%" index "%HERE%CallsRename.pas" --db "%DB%" >NUL
REM 1.44.1: rename proves every occurrence and writes through the compile gate. With no library and no project
REM it refuses and writes nothing. The positive path, through a real build: tests\refactor\run_rename_param.ps1.
"%EXE%" rename --qname Calls.TWidget.Compute --to Calc --db "%DB%" > "%HERE%t36_out.txt" 2>&1
set RC=%ERRORLEVEL%
type "%HERE%t36_out.txt"
if not "%RC%"=="2" (echo FAIL: expected exit 2, got %RC% && exit /b 1)
findstr /c:"refused [" "%HERE%t36_out.txt" >NUL || (echo FAIL: no named refusal && exit /b 1)
findstr /c:"function Calc" "%HERE%CallsRename.pas" >NUL && (echo FAIL: a refused rename wrote the file && exit /b 1)
if exist "%HERE%CallsRename.pas.bak" (echo FAIL: a refused rename left a backup && exit /b 1)
del /q "%HERE%CallsRename.pas" "%HERE%t36.sqlite" "%HERE%t36_out.txt"
echo PASS
exit /b 0
