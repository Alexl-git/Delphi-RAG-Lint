@echo off
call "%~dp0_vsenv.bat" 32 >NUL
"C:\Projects\tree-sitter-delphi13\node_modules\tree-sitter-cli\tree-sitter.exe" build "C:\Projects\tree-sitter-delphi13" -o "C:\Projects\Delphi-RAG-lint\third_party\dll-win32\tree-sitter-delphi13.dll"
echo EXIT:%errorlevel%
