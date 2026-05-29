@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars32.bat" >NUL 2>NUL
"C:\Projects\tree-sitter-delphi13\node_modules\tree-sitter-cli\tree-sitter.exe" build "C:\Projects\tree-sitter-dfm" -o "C:\Projects\Delphi-RAG-lint\third_party\dll-win32\tree-sitter-dfm.dll"
echo EXIT:%errorlevel%
