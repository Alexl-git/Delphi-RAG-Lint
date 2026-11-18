@echo off
REM Build both field repository editor builds (each carries its own --selftest); fails if either fails.
setlocal
call "%~dp0_build_field_repo_local.bat"
if not "%errorlevel%"=="0" exit /b 1
call "%~dp0_build_field_repo_std_local.bat"
echo BUILD_EXITCODE=%errorlevel%
