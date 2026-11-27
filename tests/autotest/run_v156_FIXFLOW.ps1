<#
  run_v156_FIXFLOW.ps1 -- 1.56 lane FIX-FLOW: the flow graph of FlowChecks is built with the noreturn
  oracle, and a record with a Create function is not a leaked object.
  Fixture tests\fixtures\v156\FIXFLOW: a FIRE line must report the rule named after it, every other line
  must stay silent for function-result-not-set and object-leak.
    CrossUnitFail  -- `if A then Exit(1); Fail('x');` with Fail noreturn in ANOTHER unit: silent
    HashIt         -- `THashSHA2.Create` (an RTL record): silent
    RealMissing    -- a real missing Result: still FIRES (positive control)
  RED = an engine built before this lane (-Exe): 2 extra findings; GREEN = this lane's engine.
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v156-fixflow-$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$script:Failed = 0
$script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:Failed++ }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fix = (Resolve-Path "$PSScriptRoot\..\fixtures\v156\FIXFLOW").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$Src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $Src | Out-Null
Copy-Item "$Fix\*.pas" $Src
$Db  = Join-Path $WorkDir 'p.sqlite'
$Cfg = Join-Path $WorkDir 'cfg.json'
[IO.File]::WriteAllText($Cfg, '{}', [Text.Encoding]::ASCII)
& { $ErrorActionPreference = 'Continue'; & $Exe index $Src --db $Db 2>&1 | ForEach-Object { "$_" } } | Out-Null
Check 'index exit 0' ($LASTEXITCODE -eq 0) "rc=$LASTEXITCODE"

$keys = @()
foreach ($rule in 'function-result-not-set', 'object-leak') {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $Db --config $Cfg --rule $rule --json 2>$null }
  $txt = ($raw | Where-Object { $_ -is [string] }) -join "`n"
  $i = $txt.IndexOf('[')
  if ($i -ge 0) {
    $keys += @($txt.Substring($i) | ConvertFrom-Json | ForEach-Object { $_ } | ForEach-Object {
      $r = if ($_.rule_id) { $_.rule_id } else { $_.rule }
      $p = if ($_.file_path) { $_.file_path } elseif ($_.path) { $_.path } else { $_.file }
      "{0}:{1} {2}" -f (Split-Path $p -Leaf), $_.start_line, $r })
  }
}
$want = @(); $n = 0
foreach ($l in Get-Content (Join-Path $Src 'uFf.pas')) { $n++; if ($l -match '// FIRE (\S+)') { $want += "uFf.pas:$n $($Matches[1])" } }
Check 'the fixture has one firing control' ($want.Count -eq 1) "$($want.Count)"
foreach ($w in $want) { Check "fires $w (a real missing Result)" ($keys -contains $w) ($keys -join ', ') }
$extra = @($keys | Where-Object { $want -notcontains $_ })
Check 'no false finding after a cross-unit noreturn call, none for THashSHA2.Create' ($extra.Count -eq 0) ($extra -join ', ')

Write-Host ("{0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if (($WorkDir -like "$env:TEMP\drag-lint-v156-fixflow-$PID*") -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
