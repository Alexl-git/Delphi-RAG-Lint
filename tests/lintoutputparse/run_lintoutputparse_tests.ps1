<#
  run_lintoutputparse_tests.ps1 -- compiles and runs LintOutputParseTests.dpr.

  Pins INBOX-livediag-parser-line1-fallback.md: the live-lint parser turned any
  unparseable line into a finding on LINE 1 of the user's file, because
  StrToIntDef defaulted to 1 and the guards (two colons left of a bracket) are
  satisfied by "drag-lint: note: ..." and by every Windows path. RunCapture
  gives stdout and stderr one pipe, so engine notes interleave with findings
  mid-word -- that is not hypothetical, it was observed.

  Same shape as tests\searchparse\: the logic lives in a PURE unit
  (DragLint.Plugin.LintOutputParse) precisely so a console harness can reach it.
  DragLint.Plugin.LiveDiagnostics itself pulls in ToolsAPI and Vcl.ExtCtrls and
  cannot be linked here.
#>
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dir = $PSScriptRoot
$out = cmd /c "call `"$rs`" && cd /d `"$dir`" && dcc64 -B -E`"$dir`" `"$dir\LintOutputParseTests.dpr`"" 2>&1
$err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 10; exit 1 }
& "$dir\LintOutputParseTests.exe"
exit $LASTEXITCODE
