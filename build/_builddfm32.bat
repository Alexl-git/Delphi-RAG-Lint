@echo off
REM Build tree-sitter-dfm.dll for Win32 (x86) via cl.exe and stage it to dll-win32 AND dll.
REM 149 DF: "tree-sitter build" ignores the vcvars32 environment and links an x64 DLL even under
REM _vsenv.bat 32 (PE machine 0x8664 verified), so the Win32 route compiles src\parser.c with cl
REM /MACHINE:X86 the way _builddfm32_manual.bat does. parser.c includes tree_sitter/parser.h
REM relative to its own folder, so no extra include path is needed.
call "%~dp0_vsenv.bat" 32 >NUL 2>NUL
cd /D "C:\Projects\Delphi-RAG-lint\build"
cl /nologo /O2 /LD /MD /D_CRT_SECURE_NO_WARNINGS /wd4146 /wd4244 /wd4267 /wd4090 ^
   "C:\Projects\tree-sitter-DFM\src\parser.c" ^
   /Fe:"C:\Projects\Delphi-RAG-lint\third_party\dll-win32\tree-sitter-dfm.dll" ^
   /link /EXPORT:tree_sitter_dfm /MACHINE:X86
if errorlevel 1 goto :done
copy /Y "C:\Projects\Delphi-RAG-lint\third_party\dll-win32\tree-sitter-dfm.dll" "C:\Projects\Delphi-RAG-lint\third_party\dll\tree-sitter-dfm.dll" >NUL
del /Q "C:\Projects\Delphi-RAG-lint\build\parser.obj" "C:\Projects\Delphi-RAG-lint\third_party\dll-win32\tree-sitter-dfm.exp" "C:\Projects\Delphi-RAG-lint\third_party\dll-win32\tree-sitter-dfm.lib" >NUL 2>NUL
:done
echo EXIT:%errorlevel%
