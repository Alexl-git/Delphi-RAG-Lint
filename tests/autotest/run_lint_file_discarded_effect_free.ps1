<#
  run_lint_file_discarded_effect_free.ps1 -- `lint <file> --db <db>` must
  report discarded-effect-free-result with NO --rule, as lint-all does.

  The rule is ON by default since 1.20.1 (owner ruling DEC-7), but it is an
  OptedIn-gated project rule and DoLint handed TProjectLintRules.Run no opt-in
  list, so the per-file verb -- the one the IDE gutter runs -- never reported
  it unless --rule named it (lane A5). With a store that CONTAINS the file the
  answer for one file is exact (its own call sites), so the verb now opts it in
  and narrows the scan to that file.

  Fixture: tests\lint-project\purity-rules\uRules.pas, copied to a scratch dir
  and indexed into a scratch DB (index runs the purity resolve stage).

    c1  bare `lint <file> --db` reports it once, at the `Twice(3);` line
    c2  lint-all on the same DB agrees (positive control: the fixture and the
        index really do produce the finding)
    c3  `--disable discarded-effect-free-result` turns it off again (ON is not
        "cannot be turned off")

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_file_defr_$PID",
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([bool]$ok, [string]$what) {
  if ($ok) { if (-not $Quiet) { Write-Host "PASS  $what" } }
  else     { Write-Host "FAIL  $what" -ForegroundColor Red; $script:fail = $true }
}
function Parse-Findings([string[]]$Raw) {
  $txt = ($Raw -join "`n"); $b = $txt.IndexOf('[')
  $out = @(); if ($b -ge 0) { try { $out = @($txt.Substring($b) | ConvertFrom-Json) } catch { $out = @() } }
  return ,@($out)
}

$exePath = (Resolve-Path $Exe).Path
$rule    = 'discarded-effect-free-result'
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$fixture = Join-Path $WorkDir 'uRules.pas'
Copy-Item "$PSScriptRoot\..\lint-project\purity-rules\uRules.pas" $fixture -Force
$db = Join-Path $WorkDir 'defr.sqlite'

Push-Location $env:TEMP
try {
  & $exePath index $WorkDir --db $db *> $null
  $stmtLine = (Select-String -LiteralPath $fixture -Pattern '^\s*Twice\(3\);' | Select-Object -First 1).LineNumber

  $f1 = Parse-Findings (& $exePath lint $fixture --db $db --json 2>$null)
  $d1 = @($f1 | Where-Object { $_.rule -eq $rule })
  Check (($d1.Count -eq 1) -and ($d1[0].start_line -eq $stmtLine)) "c1 lint <file> --db reports $rule once at line $stmtLine (got $($d1.Count): $(($d1 | ForEach-Object start_line) -join ','))"

  $f2 = Parse-Findings (& $exePath lint-all --db $db --format json 2>$null)
  $d2 = @($f2 | Where-Object { $_.rule -eq $rule })
  Check ($d2.Count -eq 1) "c2 control: lint-all reports $rule once (got $($d2.Count))"

  $f3 = Parse-Findings (& $exePath lint $fixture --db $db --json --disable $rule 2>$null)
  $d3 = @($f3 | Where-Object { $_.rule -eq $rule })
  Check (($d3.Count -eq 0) -and ($f3.Count -gt 0)) "c3 --disable $rule silences it (got $($d3.Count), other findings $($f3.Count))"
} finally {
  Pop-Location
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:fail) { Write-Host 'run_lint_file_discarded_effect_free: FAIL'; exit 1 }
Write-Host 'run_lint_file_discarded_effect_free: PASS'
exit 0
