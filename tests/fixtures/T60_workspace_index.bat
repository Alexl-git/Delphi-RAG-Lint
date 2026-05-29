@echo off
setlocal
set HERE=%~dp0
set EXE=%HERE%..\..\third_party\dll\drag-lint.exe
mkdir "%HERE%T60_ws" 2>NUL
mkdir "%HERE%T60_ws\proj1" 2>NUL
copy /Y "%HERE%Calls.pas" "%HERE%T60_ws\proj1\" >NUL
echo {"name":"T60","projects":[{"path":"proj1","scan_dir":true}],"shared_db":"shared.sqlite"} > "%HERE%T60_ws\.drag-lint-workspace.json"
"%EXE%" workspace index --config "%HERE%T60_ws\.drag-lint-workspace.json" > "%HERE%t60_out.txt"
type "%HERE%t60_out.txt"
if not exist "%HERE%T60_ws\shared.sqlite" (echo FAIL: shared db not created && exit /b 1)
echo PASS
rmdir /s /q "%HERE%T60_ws"
exit /b 0
