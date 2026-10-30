@echo off
REM build_fixture_exe.bat <name> -- compiles tests\fixtures\<name>.dpr to
REM tests\fixtures\<name>.exe (Win64) before the doctest driver runs it.
REM
REM WHY. run_v021_doctests.bat ran T2..T7 as prebuilt .exe files, and *.exe is
REM gitignored, so in a fresh checkout the six exes do not exist: cmd printed
REM "not recognized" to stderr, the section set FAILED=1 with no FAIL: line,
REM and the wrapper saw a failing exit code it could not explain (backlog L#30).
REM Building them here makes the sections run in any checkout, and a compile
REM error now prints "FAIL: build failed" plus the compiler output.
REM
REM Same quoting rules as T27/T28 (see the note there): %HERE% and the src
REM paths contain no spaces, so they are not quoted. DCUs go to a temp folder
REM so this build never drops .dcu files into src\. The unit path mirrors
REM DCC_UnitSearchPath and DCC_Namespace in src\cli\drag-lint.dproj.
setlocal
set HERE=%~dp0
set NAME=%~1
if "%NAME%"=="" (echo FAIL: build_fixture_exe.bat needs a fixture name && exit /b 1)
set S=%HERE%..\..\src
set DCU=%TEMP%\draglint_fixture_dcu
if not exist "%DCU%" mkdir "%DCU%"
if exist "%HERE%%NAME%.exe" del /q "%HERE%%NAME%.exe"
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" >NUL
dcc64 -Q -E%HERE% "-NU%DCU%" -NSSystem;Xml;Data;Datasnap;Web;Soap;Winapi;System.Win;Data.Win;Xml.Win -U%S%\preprocess;%S%\core;%S%\config;%S%\context;%S%\diagnostics;%S%\doc;%S%\forms;%S%\index;%S%\lint;%S%\lsp;%S%\mcp;%S%\output;%S%\parser;%S%\project;%S%\query;%S%\refactor;%S%\report;%S%\resolver;%S%\sql;%S%\storage;%S%\workspace;%S%\analysis;%S%\..\third_party\delphi-tree-sitter %HERE%%NAME%.dpr > "%HERE%%NAME%_build.txt" 2>&1
if not exist "%HERE%%NAME%.exe" (echo FAIL: build failed: %NAME% && type "%HERE%%NAME%_build.txt" && exit /b 1)
REM The storage loads sqlite3.dll from the EXE's own folder (FireDAC -314
REM otherwise), and the parser needs the tree-sitter DLLs: stage the engine's.
copy /y "%HERE%..\..\third_party\dll-win64\*.dll" "%HERE%" >NUL
exit /b 0
