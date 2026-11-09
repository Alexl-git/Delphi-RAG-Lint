@echo off
REM Usage: %~nx0 [grammar-checkout] [output-dll]
REM   grammar-checkout  default C:\Projects\tree-sitter-delphi13 (a worktree path works)
REM   output-dll        default C:\Projects\Delphi-RAG-lint\third_party\<dir>\tree-sitter-delphi13.dll
set "GRAM=%~1"
if "%GRAM%"=="" set "GRAM=C:\Projects\tree-sitter-delphi13"
REM a fresh worktree has no node_modules: borrow the main checkout's (tree-sitter-cli, headers)
set "GNM=%GRAM%\node_modules"
if not exist "%GNM%" set "GNM=C:\Projects\tree-sitter-delphi13\node_modules"
set "OUT=%~2"
if "%OUT%"=="" set "OUT=C:\Projects\Delphi-RAG-lint\third_party\dll-win32\tree-sitter-delphi13.dll"
call "%~dp0_vsenv.bat" 32 >NUL
"%GNM%\tree-sitter-cli\tree-sitter.exe" build "%GRAM%" -o "%OUT%"
echo EXIT:%errorlevel%