# Build + run the --fail-on exit-code policy unit tests (bare dcc64, Win64).
$rs  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dir = $PSScriptRoot
$out = cmd /c "call `"$rs`" && cd /d `"$dir`" && dcc64 -B -E`"$dir`" `"$dir\ExitCodeTests.dpr`"" 2>&1
$err = $out | Select-String -Pattern "\bError\b|E2\d{3}|F2\d{3}|Fatal"
if ($err) { Write-Host "BUILD FAILED:"; $err | Select-Object -First 10; exit 1 }
& "$dir\ExitCodeTests.exe"
$unitPass = $LASTEXITCODE -eq 0

# CLI-level check (v0.81 review Minor: exit code from survivors, not raw
# findings). suppressed_only_fixture.pas trips ONLY 'boolean-flag-parameter',
# which is OFF-by-default. A bare run must report "0 finding(s)" AND exit 0
# -- proving FinalizeAndOutput derives its --fail-on-absent default from the
# post-ShouldKeep Survivors set (CLI.pas ~4624), not from the raw AFindings
# the caller collected before suppression.
$repo = (Resolve-Path (Join-Path $dir "..\..")).Path
$exe  = Join-Path $repo "third_party\dll-win64\drag-lint.exe"
$fx   = Join-Path $dir "suppressed_only_fixture.pas"
$cliPass = 0; $cliFail = 0
function CliCheck($n, $c) { if ($c) { $script:cliPass++; Write-Host "PASS  $n" } else { $script:cliFail++; Write-Host "FAIL  $n" } }

$bare = & $exe lint $fx 2>$null | Out-String
CliCheck "suppressed-only: bare run prints 0 finding(s)" ($bare -match '0 finding\(s\)')
CliCheck "suppressed-only: bare run exits 0"              ($LASTEXITCODE -eq 0)

$enabled = & $exe lint $fx --enable boolean-flag-parameter 2>$null | Out-String
CliCheck "suppressed-only: --enable makes the rule fire"  ($enabled -match 'boolean-flag-parameter')
CliCheck "suppressed-only: --enable run exits 1"           ($LASTEXITCODE -eq 1)

Write-Host ""
Write-Host "exitcode-cli-tests: $cliPass pass / $cliFail fail / $($cliPass + $cliFail) total"

if (-not $unitPass -or $cliFail -gt 0) { exit 1 } else { exit 0 }
