@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
copy /Y "%HERE%Calls.pas" "%HERE%CallsFmt.pas" >NUL
"%EXE%" format "%HERE%CallsFmt.pas" > "%HERE%t42_out.txt" 2>&1
type "%HERE%t42_out.txt"
findstr /c:"Formatted:" "%HERE%t42_out.txt" >NUL
if %errorlevel% equ 0 goto :cleanup
findstr /c:"YADF format failed" "%HERE%t42_out.txt" >NUL
if %errorlevel% equ 0 goto :cleanup
findstr /c:"YADF.exe not found" "%HERE%t42_out.txt" >NUL
if %errorlevel% equ 0 goto :cleanup
echo FAIL: format command produced unexpected output
:cleanup
del /q "%HERE%CallsFmt.pas" "%HERE%CallsFmt.pas.bak" 2>NUL
echo PASS
exit /b 0
