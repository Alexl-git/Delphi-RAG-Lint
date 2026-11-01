@echo off
REM Build tree-sitter-delphi13.dll for Win64 via cl.exe (matches grammar32 pattern).
call "%~dp0_vsenv.bat" 64 >NUL 2>NUL
cd /D "C:\Projects\Delphi-RAG-lint\build"
cl /nologo /O2 /LD /MD /D_CRT_SECURE_NO_WARNINGS /wd4146 /wd4244 /wd4267 /wd4090 ^
   /I "C:\Projects\tree-sitter-delphi13\node_modules\tree-sitter\vendor\tree-sitter\lib\include" ^
   "C:\Projects\tree-sitter-delphi13\src\parser.c" ^
   "C:\Projects\tree-sitter-delphi13\src\scanner.c" ^
   /Fe:"C:\Projects\Delphi-RAG-lint\third_party\dll-win64\tree-sitter-delphi13.dll" ^
   /link /EXPORT:tree_sitter_delphi13 /MACHINE:X64
echo EXIT:%errorlevel%
