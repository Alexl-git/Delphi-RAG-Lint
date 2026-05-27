call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >NUL
"C:\Projects\tree-sitter-delphi13\node_modules\tree-sitter-cli\tree-sitter.exe" build "C:\Projects\tree-sitter-delphi13" -o "C:\Projects\Delphi-RAG-lint\third_party\dll\tree-sitter-delphi13.dll"
echo EXIT:%errorlevel%
