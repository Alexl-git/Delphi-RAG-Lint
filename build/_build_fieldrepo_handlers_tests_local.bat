@echo off
REM Build the DLFR handler (TT-HANDLERS) test runner (Win64) from THIS checkout.
REM Usage: _build_fieldrepo_handlers_tests_local.bat [outdir]   (the tree-sitter DLLs are staged beside the exe)
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0..\tests\fieldrepo"
set OUT=%~1
if "%OUT%"=="" set OUT=.
if not exist "%OUT%\dcu" mkdir "%OUT%\dcu"
set S=..\..\src
dcc64 -B -NU"%OUT%\dcu" -E"%OUT%" -U"%S%\sql;%S%\lsp;%S%\parser;%S%\core;%S%\diagnostics;%S%\index;%S%\storage;%S%\lint;%S%\analysis;%S%\preprocess;..\..\third_party\delphi-tree-sitter" -NSSystem;Winapi;System.Win;Data;FireDAC HandlersTests.dpr
set RC=%errorlevel%
copy /Y "..\..\third_party\dll-win64\tree-sitter*.dll" "%OUT%" >NUL
echo BUILD_EXITCODE=%RC%
