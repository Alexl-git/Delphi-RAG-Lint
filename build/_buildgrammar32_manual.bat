@echo off
REM Manually build tree-sitter-delphi13.dll for Win32 via cl.exe.
REM Usage: %~nx0 [grammar-checkout] [output-dll]
REM   grammar-checkout  default C:\Projects\tree-sitter-delphi13 (a worktree path works)
REM   output-dll        default C:\Projects\Delphi-RAG-lint\third_party\dll-win32\tree-sitter-delphi13.dll
REM THREE-DIRECTORY RULE (third_party\; see build\README.md):
REM   dll-win64\  x64 tree-sitter*.dll + the Win64 engine   <- every 64-bit build writes here
REM   dll-win32\  x86 tree-sitter*.dll + IDE BPL/DCP        <- every 32-bit build writes here
REM   dll\        LEGACY x86 source copies (deploy-staged.bat refreshes dll-win32 from them);
REM               never write an x64 DLL or an engine exe there (run_no_engine_beside_bpl.ps1)
set "GRAM=%~1"
if "%GRAM%"=="" set "GRAM=C:\Projects\tree-sitter-delphi13"
REM a fresh worktree has no node_modules: borrow the main checkout's (tree-sitter-cli, headers)
set "GNM=%GRAM%\node_modules"
if not exist "%GNM%" set "GNM=C:\Projects\tree-sitter-delphi13\node_modules"
set "OUT=%~2"
if "%OUT%"=="" set "OUT=C:\Projects\Delphi-RAG-lint\third_party\dll-win32\tree-sitter-delphi13.dll"
call "%~dp0_vsenv.bat" 32 >NUL 2>NUL
cd /D "%~dp0"
cl /nologo /O2 /LD /MD /D_CRT_SECURE_NO_WARNINGS /wd4146 /wd4244 /wd4267 /wd4090 ^
   /I "%GNM%\tree-sitter\vendor\tree-sitter\lib\include" ^
   "%GRAM%\src\parser.c" ^
   "%GRAM%\src\scanner.c" ^
   /Fe:"%OUT%" ^
   /link /EXPORT:tree_sitter_delphi13 /MACHINE:X86
echo EXIT:%errorlevel%