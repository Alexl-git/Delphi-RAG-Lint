@echo off
setlocal enabledelayedexpansion
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
set ROOT=%TEMP%\dl_scantest
set DB=%HERE%t43_scan.sqlite
set DB2=%HERE%t43_excl.sqlite

rem ---- build a throwaway source tree ----
rmdir /s /q "%ROOT%" 2>NUL
mkdir "%ROOT%\src"
mkdir "%ROOT%\Old_Backup"
mkdir "%ROOT%\Vendor"
mkdir "%ROOT%\db"
mkdir "%ROOT%\excludeme"

echo unit Good; interface implementation end.> "%ROOT%\src\Good.pas"
echo unit Bak; interface implementation end.> "%ROOT%\Old_Backup\Bak.pas"
echo unit Vend; interface implementation end.> "%ROOT%\Vendor\Vend.pas"
echo.> "%ROOT%\Vendor\.scanignore"
echo unit Excl; interface implementation end.> "%ROOT%\excludeme\Excl.pas"
echo CREATE TABLE MSGOODTBL ^(ID INTEGER^);> "%ROOT%\db\MS1.SQL"
echo CREATE TABLE NOSCANTBL ^(ID INTEGER^);> "%ROOT%\db\query.sql"
echo object Form1: TForm1 end> "%ROOT%\src\Main.dfm"

del "%DB%" "%DB2%" 2>NUL

rem ---- index with all filters active ----
"%EXE%" index "%ROOT%" --db "%DB%" >NUL

rem Good.pas indexed
"%EXE%" query --name Good --db "%DB%" | findstr /c:"1 match" >NUL || (echo FAIL: Good.pas not indexed && exit /b 1)
rem *BACKUP* folder pruned
"%EXE%" query --name Bak --db "%DB%" | findstr /c:"0 match" >NUL || (echo FAIL: backup folder was scanned && exit /b 1)
rem .scanignore folder pruned
"%EXE%" query --name Vend --db "%DB%" | findstr /c:"0 match" >NUL || (echo FAIL: .scanignore folder was scanned && exit /b 1)
rem MS*.SQL indexed (table symbol present)
"%EXE%" query --name MSGOODTBL --db "%DB%" | findstr /c:"1 match" >NUL || (echo FAIL: MS1.SQL table not indexed && exit /b 1)
rem non-MS .sql skipped
"%EXE%" query --name NOSCANTBL --db "%DB%" | findstr /c:"0 match" >NUL || (echo FAIL: non-MS .sql was scanned && exit /b 1)
rem DFM indexed
"%EXE%" query --name Form1 --db "%DB%" | findstr /c:"1 match" >NUL || (echo FAIL: .dfm not indexed && exit /b 1)

rem ---- --exclude-under prunes a subtree ----
"%EXE%" index "%ROOT%" --db "%DB2%" --exclude-under "%ROOT%\excludeme" >NUL
"%EXE%" query --name Good --db "%DB2%" | findstr /c:"1 match" >NUL || (echo FAIL: Good missing under exclude run && exit /b 1)
"%EXE%" query --name Excl --db "%DB2%" | findstr /c:"0 match" >NUL || (echo FAIL: --exclude-under did not prune && exit /b 1)

rmdir /s /q "%ROOT%" 2>NUL
echo PASS
exit /b 0
