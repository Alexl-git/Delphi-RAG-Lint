@echo off
REM _vsenv.bat <32|64> -- load the MSVC x86/x64 build environment from WHATEVER Visual Studio is installed.
REM The _build*.bat wrappers used to hard-code "...\Visual Studio\2022\BuildTools"; this machine has VS 18
REM (Program Files, not x86), so every wrapper died with "system cannot find the path". vswhere ships with the
REM VS installer at a fixed location and names the newest install that has the C++ x86/x64 tools.
REM Fixed installer path (vswhere is always here); no for-block, a ")" in a path would end it early.
set "VSINST="
set "VSW=C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
set "VSOUT=%TEMP%\_vsenv_%RANDOM%%RANDOM%.txt"
"%VSW%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath > "%VSOUT%"
if exist "%VSOUT%" set /p VSINST=<"%VSOUT%"
if exist "%VSOUT%" del "%VSOUT%" >NUL 2>NUL
if not defined VSINST goto :none
call "%VSINST%\VC\Auxiliary\Build\vcvars%1.bat"
exit /b %ERRORLEVEL%
:none
echo ERROR: no Visual Studio with the C++ x86/x64 tools found by vswhere
exit /b 1
