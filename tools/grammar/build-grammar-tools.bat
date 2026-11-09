@echo off
REM build-grammar-tools.bat [grammar-checkout] [out-dir] -- build tsdiff / tserr / tsparse (x64, cl.exe).
REM   grammar-checkout: a tree-sitter-delphi13 checkout whose node_modules holds the tree-sitter runtime
REM                     sources (default C:\Projects\tree-sitter-delphi13); a lane worktree without
REM                     node_modules works as long as the default checkout has them.
REM   out-dir:          where the exes go (default tools\grammar\bin, gitignored).
REM The runtime (lib.c) is compiled once into lib.obj beside the exes. 7-bit ASCII, CRLF.
setlocal
set "HERE=%~dp0"
set "GRAMMAR=%~1"
if "%GRAMMAR%"=="" set "GRAMMAR=C:\Projects\tree-sitter-delphi13"
set "OUT=%~2"
if "%OUT%"=="" set "OUT=%HERE%bin"
set "TSLIB=%GRAMMAR%\node_modules\tree-sitter\vendor\tree-sitter\lib"
if not exist "%TSLIB%\src\lib.c" set "TSLIB=C:\Projects\tree-sitter-delphi13\node_modules\tree-sitter\vendor\tree-sitter\lib"
if not exist "%TSLIB%\src\lib.c" echo ERROR: tree-sitter runtime lib.c not found under %TSLIB% & exit /b 2
call "%HERE%..\..\build\_vsenv.bat" 64 >NUL 2>NUL
if errorlevel 1 echo ERROR: no MSVC x64 environment & exit /b 2
if not exist "%OUT%" mkdir "%OUT%"
cd /d "%OUT%"
cl /nologo /O2 /MD /c /D_CRT_SECURE_NO_WARNINGS /I "%TSLIB%\include" /I "%TSLIB%\src" "%TSLIB%\src\lib.c"
if errorlevel 1 exit /b 1
for %%T in (tsdiff tserr tsparse tsblank) do (
  cl /nologo /O2 /MD /D_CRT_SECURE_NO_WARNINGS /I "%TSLIB%\include" "%HERE%%%T.c" lib.obj /Fe:"%OUT%\%%T.exe"
  if errorlevel 1 exit /b 1
)
echo BUILD_EXITCODE=0
exit /b 0