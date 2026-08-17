@echo off
setlocal
set HERE=%~dp0
set IDELIB=C:\Program Files (x86)\Embarcadero\Studio\37.0\lib\win64\release
REM The nested `cmd /c "call ""..."" && ..."` form here never reached the
REM compiler: cmd resolved the doubled quotes to '""C:\Program' and reported
REM "is not recognized as an internal or external command". So this fixture had
REM been failing on its own quoting, not on anything it set out to test -- and
REM being invisible to the battery, nobody saw it. rsvars is called directly;
REM setlocal (line 2) already contains the environment it exports.
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" >NUL
REM NO PIPE. Piping to findstr made cmd re-parse the command line and split
REM %IDELIB% at the space in "C:\Program Files (x86)", so dcc64 was handed
REM `Files` as its project and died with F1026 'Files.dpr' not found. Redirect
REM straight to the file instead; the filter it replaced only hid a banner line.
REM A TRAILING BACKSLASH BEFORE A CLOSING QUOTE ESCAPES IT. %HERE% ends in '\',
REM so "-E%HERE%" is "-E...\fixtures\" -- Windows argv parsing reads that final
REM \" as a literal quote, the argument never closes, and the following ones are
REM swallowed into it. dcc64 then saw `Files` (from "Program Files") as a bare
REM argument, took it for the project, and died F1026 'Files.dpr' not found.
REM That is why the original -E""%HERE%"" form failed too, and why quoting the
REM whole switch did not help either.
REM %HERE% and the src path contain no spaces, so they need no quotes at all;
REM %IDELIB% does contain spaces but has NO trailing backslash, so quoting it is
REM safe. Do not "tidy" this by quoting the others.
REM src\core is on the path because HoverForm uses DRagLint.Hover.Contrast,
REM which lives there, not beside it in src\delphi-plugin. The unit moved (or
REM the form gained the dependency) at some point after this fixture was
REM written, and because the fixture was never run, nothing reported F2613.
dcc64 -E%HERE% -U%HERE%..\..\src\delphi-plugin;%HERE%..\..\src\core "-U%IDELIB%" -LUdesignide %HERE%T31_hoverform.dpr > "%HERE%t31_build.txt" 2>&1
if not exist "%HERE%T31_hoverform.exe" (echo FAIL: build failed && type "%HERE%t31_build.txt" && exit /b 1)
"%HERE%T31_hoverform.exe" > "%HERE%t31_out.txt"
type "%HERE%t31_out.txt"
findstr /c:"OK" "%HERE%t31_out.txt" >NUL || (echo FAIL: hover form unit did not print OK && exit /b 1)
echo PASS
exit /b 0
