@echo off
setlocal
set HERE=%~dp0
if not defined EXE set EXE=%HERE%..\..\third_party\dll-win64\drag-lint.exe
set DB=%HERE%t42_outline.sqlite
set SRC=%HERE%Kinds.pas

del "%DB%" 2>NUL

rem Index the single fixture file fresh so the test is self-contained.
"%EXE%" index "%SRC%" --db "%DB%" >NUL

rem --- text format: every symbol in the file, ordered by position ---
"%EXE%" outline --file "%SRC%" --db "%DB%" > "%HERE%t42_text.txt"
type "%HERE%t42_text.txt"
findstr /c:"unit"      "%HERE%t42_text.txt" | findstr /c:"Kinds" >NUL || (echo FAIL: unit row missing && exit /b 1)
findstr /c:"Kinds.TShape" "%HERE%t42_text.txt" >NUL || (echo FAIL: class row missing && exit /b 1)
findstr /c:"Kinds.TShape.Area" "%HERE%t42_text.txt" >NUL || (echo FAIL: method row missing && exit /b 1)

rem --- json format: machine-readable shape consumed by the Structure form ---
"%EXE%" outline --file "%SRC%" --db "%DB%" --format json > "%HERE%t42_json.txt"
findstr /c:"\"kind\":"  "%HERE%t42_json.txt" >NUL || (echo FAIL: json kind key missing && exit /b 1)
findstr /c:"\"line\":"  "%HERE%t42_json.txt" >NUL || (echo FAIL: json line key missing && exit /b 1)
findstr /c:"\"qname\":" "%HERE%t42_json.txt" >NUL || (echo FAIL: json qname key missing && exit /b 1)

rem --- path tolerance: a path with a redundant ..\ segment must still resolve ---
"%EXE%" outline --file "%HERE%.\Kinds.pas" --db "%DB%" > "%HERE%t42_tol.txt"
findstr /c:"Kinds.TShape" "%HERE%t42_tol.txt" >NUL || (echo FAIL: path tolerance broke && exit /b 1)

echo PASS
exit /b 0
