<#
  run_include_false_positives.ps1 -- two lint-all false positives on include files (wave 152c lane INCR, M4 + M3).

  M4  frag\      a uses-fragment include (`uses {$I FragUses.inc}`, the .inc is a bare list of unit names)
                 is not a parse error: no parser-error / syntax-error on it.
                 fragcode\  a REAL syntax error in an include that is included as code still reports both.
                 fragboth\  a fragment included BOTH in a uses clause and as code still reports both.
  M3  unusedinc\ unused-unit-in-uses counts a symbol declared in an include of the used unit:
                 UnB references TUnRec (declared in UnTypes.inc, included by UnA) -> silent;
                 UnC uses UnA and references nothing -> still fires (the positive control: the rule is on).

  RED on the 1.50.0-alpha base: frag reports 2 errors, UnB fires. GREEN with lane INCR.
  Usage: pwsh -File tests\lint-project\cycle-edge-in-include\run_include_false_positives.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "$PSScriptRoot\..\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
. "$repo\tests\autotest\lib\HermeticEngine.ps1"; $exePath = Get-HermeticEngine $exePath
$scratch = Join-Path ([IO.Path]::GetTempPath()) "draglint_incfp_$PID"
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  Write-Host ("[{0}] {1}{2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}
function Parse-Findings([string[]]$Raw) {
  $txt = ($Raw -join "`n"); $b = $txt.IndexOf('[')
  $out = @(); if ($b -ge 0) { try { $out = @($txt.Substring($b) | ConvertFrom-Json) } catch { $out = @() } }
  if ($null -eq $out) { $out = @() }
  return ,@($out)
}
function Scenario([string]$Name, [string[]]$LintArgs) {
  $dir = Join-Path $scratch $Name
  [void](New-Item -ItemType Directory -Force -Path $dir)
  Copy-Item (Join-Path $PSScriptRoot "$Name\*") $dir
  $db = Join-Path $scratch "$Name.sqlite"
  & $exePath index $dir --db $db 2>&1 | Out-Null
  $raw = & $exePath lint-all --db $db --library-db none @LintArgs --format json 2>$null
  $parsed = Parse-Findings $raw
  return ,@($parsed)
}
function Leaf($F) { Split-Path $F.file_path -Leaf }
try {
  [void](New-Item -ItemType Directory -Force -Path $scratch)

  $f0 = Scenario 'frag' @('--enable', 'parser-error,syntax-error')
  $fe = @($f0 | Where-Object { $_.rule -in @('parser-error', 'syntax-error') })
  Check 'M4: a uses-fragment include reports no parser-error / syntax-error' ($fe.Count -eq 0) "$($fe.Count)"
  $f1 = Scenario 'fragcode' @()
  $fe1 = @($f1 | Where-Object { $_.rule -in @('parser-error', 'syntax-error') -and (Leaf $_) -eq 'FragBroken.inc' })
  Check 'M4 control: a real syntax error in an include used as code still reports both rules' ($fe1.Count -eq 2) "$($fe1.Count)"
  $f2 = Scenario 'fragboth' @()
  $fe2 = @($f2 | Where-Object { $_.rule -in @('parser-error', 'syntax-error') -and (Leaf $_) -eq 'FragBothUses.inc' })
  Check 'M4 control: a fragment included in a uses clause AND as code still reports both rules' ($fe2.Count -eq 2) "$($fe2.Count)"

  $u = @(Scenario 'unusedinc' @('--rule', 'unused-unit-in-uses') | Where-Object { $_.rule -eq 'unused-unit-in-uses' })
  $u | ForEach-Object { Write-Host ("    {0}:{1} {2}" -f (Leaf $_), $_.start_line, $_.message.Substring(0, [Math]::Min(80, $_.message.Length))) -ForegroundColor DarkGray }
  Check 'M3: UnB (references TUnRec from the include of UnA) is not flagged' (@($u | Where-Object { (Leaf $_) -eq 'UnB.pas' }).Count -eq 0)
  Check 'M3 control: UnC (uses UnA, references nothing) is still flagged' (@($u | Where-Object { (Leaf $_) -eq 'UnC.pas' }).Count -eq 1) "$($u.Count) finding(s)"
} finally {
  if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
Write-Host ''
if ($script:fail) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0
