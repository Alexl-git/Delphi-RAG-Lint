@echo off
REM Build drag-lint.exe Win32 -> dll-win32/.
setlocal
set RSVARS="C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
call %RSVARS%
if errorlevel 1 exit /b 1

set HERE=%~dp0
set ROOT=%HERE%..

cd /D "%ROOT%\src\cli"
msbuild /t:Build /p:Config=Debug /p:Platform=Win32 /v:minimal drag-lint.dproj
if errorlevel 1 exit /b 1

copy /Y "%ROOT%\src\cli\Win32\Debug\drag-lint.exe" "%ROOT%\third_party\dll-win32\drag-lint.exe" >NUL
copy /Y "%ROOT%\src\cli\Win32\Debug\drag-lint.exe" "%ROOT%\third_party\dll\drag-lint.exe" >NUL
echo OK: staged Win32 drag-lint.exe
endlocal
