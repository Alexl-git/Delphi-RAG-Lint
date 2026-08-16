@echo off
REM Build drag-lint.exe Win64 -> dll-win64/.
setlocal
set RSVARS="C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
call %RSVARS%
if errorlevel 1 exit /b 1

set HERE=%~dp0
set ROOT=%HERE%..

cd /D "%ROOT%\src\cli"
msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal drag-lint.dproj
if errorlevel 1 exit /b 1

REM Stage the tree-sitter companions NEXT TO THE LINKED EXE, not only next to the
REM staged copy. The .pas declarations import them implicitly, so the loader needs
REM them in the exe's own directory. Without this the freshly linked
REM src\cli\Win64\Debug\drag-lint.exe -- which 51 of the 79 suites under
REM tests\autotest resolve -- cannot start: the loader falls through to PATH,
REM finds the x86 copies in third_party\dll, and dies 0xC000007B
REM STATUS_INVALID_IMAGE_FORMAT. That is a bitness mismatch, NOT a missing-DLL
REM error (which would be 0xC0000135), which is why it never looked like a
REM staging problem.
REM
REM WHAT GUARDS THIS: nothing dedicated, by choice. Remove this copy and the first
REM suite run without an explicit -Exe dies at process start, before its first
REM check, across all 51 -- loud and immediate. A .bat-level guard would be a
REM second implementation of the copy below. tests\run_battery.ps1 and
REM tests\autotest\run_exe_freshness.ps1 do not close it either: the freshness
REM guard checks exe existence and mtime-vs-newest-source only -- it never looks
REM for tree-sitter DLLs beside the exe, so it could not catch a regression here.
copy /Y "%ROOT%\third_party\dll-win64\tree-sitter*.dll" "%ROOT%\src\cli\Win64\Debug\" >NUL
if errorlevel 1 (
  echo ERROR: failed to stage tree-sitter companions into %ROOT%\src\cli\Win64\Debug
  exit /b 1
)

REM Stage the RULE CATALOGUE beside both exes. rules\ is the only TRACKED copy;
REM <exe-dir>\rules is gitignored, and until now nothing produced it -- so a
REM fresh clone had no external rules at all, and an edit to rules\*.scm was
REM INERT until someone remembered to copy it by hand. That is not theoretical:
REM the bare-except anchor fix was edited, built, and measured against the OLD
REM rule, with the whole suite passing. The Release and Win32 copies were 35 and
REM 104 files behind when this was found.
REM
REM tests\run_battery.ps1 (register K41) now hashes rules\ against both of these
REM and shouts on drift, so this copy and that check are a matched pair: the
REM build makes them right, the battery proves they stayed right.
for %%D in ("%ROOT%\src\cli\Win64\Debug" "%ROOT%\third_party\dll-win64") do (
  if not exist "%%~D\rules" mkdir "%%~D\rules"
  copy /Y "%ROOT%\rules\*.scm"  "%%~D\rules\" >NUL
  copy /Y "%ROOT%\rules\*.json" "%%~D\rules\" >NUL
  if exist "%ROOT%\rules\builtin-symbols.txt" copy /Y "%ROOT%\rules\builtin-symbols.txt" "%%~D\rules\" >NUL
)

copy /Y "%ROOT%\src\cli\Win64\Debug\drag-lint.exe" "%ROOT%\third_party\dll-win64\drag-lint.exe" >NUL
if errorlevel 1 (
  echo ERROR: failed to stage %ROOT%\third_party\dll-win64\drag-lint.exe
  exit /b 1
)
echo OK: staged Win64 drag-lint.exe + tree-sitter companions
endlocal
