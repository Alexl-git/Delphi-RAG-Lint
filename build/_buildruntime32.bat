@echo off
REM Build tree-sitter.dll for Win32 (x86) — matches the Win32 IDE plugin BPL.
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars32.bat" >NUL 2>NUL
cd /D "C:\Projects\Delphi-RAG-lint\build"
cl /nologo /O2 /LD /MD /D_CRT_SECURE_NO_WARNINGS /wd4146 /wd4244 /wd4267 /wd4090 ^
   /I "C:\Projects\tree-sitter-delphi13\node_modules\tree-sitter\vendor\tree-sitter\lib\include" ^
   /I "C:\Projects\tree-sitter-delphi13\node_modules\tree-sitter\vendor\tree-sitter\lib\src" ^
   "C:\Projects\tree-sitter-delphi13\node_modules\tree-sitter\vendor\tree-sitter\lib\src\lib.c" ^
   /Fe:"C:\Projects\Delphi-RAG-lint\third_party\dll-win32\tree-sitter.dll" ^
   /link /DEF:"C:\Projects\Delphi-RAG-lint\build\tree-sitter-runtime.def" ^
         /MACHINE:X86
echo EXIT:%errorlevel%
