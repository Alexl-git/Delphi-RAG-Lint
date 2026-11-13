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
  152c RINC: the index's DIAG / per-file error count and `lint <file>` on the fragment agree (RED on
  the INCR head: DIAG printed, 1 error, lint <file> = 2); fragcode / fragboth keep both, as controls.
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
$script:indexOut = @{}
$script:dbOf = @{}
function Scenario([string]$Name, [string[]]$LintArgs) {
  $dir = Join-Path $scratch $Name
  [void](New-Item -ItemType Directory -Force -Path $dir)
  Copy-Item (Join-Path $PSScriptRoot "$Name\*") $dir -Recurse
  $db = Join-Path $scratch "$Name.sqlite"
  $script:indexOut[$Name] = @(& $exePath index $dir --db $db 2>&1 | ForEach-Object { "$_" })
  $script:dbOf[$Name] = $db
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

  # 152c RINC: the index (DIAG / per-file error count / parse-errors=) and `lint <file>` agree with lint-all.
  function IndexDiag([string]$Name, [string]$Inc) {
    return ,@($script:indexOut[$Name] | Where-Object { $_ -match 'DIAG:' -and $_ -match [regex]::Escape($Inc) -and $_ -match 'parse error' })
  }
  function FileLintErrors([string]$Name, [string]$Inc) {
    $raw = & $exePath lint (Join-Path (Join-Path $scratch $Name) $Inc) --db $script:dbOf[$Name] --format json 2>$null
    $all = Parse-Findings $raw
    return ,@($all | Where-Object { $_.rule -in @('parser-error', 'syntax-error') })
  }
  $progress = @($script:indexOut['frag'] | Where-Object { $_ -match 'FragUses\.inc ->' })
  Check 'M4 index: the fragment progress line was printed (shape)' ($progress.Count -eq 1) "$($progress.Count)"
  Check 'M4 index: no DIAG parse error for a uses-fragment include' ((IndexDiag 'frag' 'FragUses.inc').Count -eq 0) "$((IndexDiag 'frag' 'FragUses.inc').Count)"
  Check 'M4 index: the fragment counts 0 errors on its progress line' (($progress.Count -eq 1) -and ($progress[0] -match ', 0 errors')) "$progress"
  Check 'M4 index control: an include used as code keeps its DIAG parse error' ((IndexDiag 'fragcode' 'FragBroken.inc').Count -eq 1) "$((IndexDiag 'fragcode' 'FragBroken.inc').Count)"
  Check 'M4 index control: a fragment also included as code keeps its DIAG parse error' ((IndexDiag 'fragboth' 'FragBothUses.inc').Count -eq 1) "$((IndexDiag 'fragboth' 'FragBothUses.inc').Count)"
  Check 'M4 lint <file>: a uses-fragment include reports no parser-error / syntax-error' ((FileLintErrors 'frag' 'FragUses.inc').Count -eq 0) "$((FileLintErrors 'frag' 'FragUses.inc').Count)"
  Check 'M4 lint <file> control: an include used as code still reports both rules' ((FileLintErrors 'fragcode' 'FragBroken.inc').Count -eq 2) "$((FileLintErrors 'fragcode' 'FragBroken.inc').Count)"
  Check 'M4 lint <file> control: a fragment also included as code still reports both rules' ((FileLintErrors 'fragboth' 'FragBothUses.inc').Count -eq 2) "$((FileLintErrors 'fragboth' 'FragBothUses.inc').Count)"

  # 152c RINC2: the index verdict does not depend on the walk order. fragorder: the fragment sits
  # above its host's folder, so a fresh directory index reads it FIRST; fragordboth: one host
  # includes it in a uses clause BEFORE it is read, a second host as code AFTER (lint-all reports
  # it); fragordcode (control): an include read before its code host keeps its DIAG.
  function ProgressAt([string]$Name, [string]$Leaf) {
    $lines = $script:indexOut[$Name]
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match ([regex]::Escape($Leaf) + ' ->')) { return $i } }
    return -1
  }
  [void](Scenario 'fragorder' @())
  [void](Scenario 'fragordcode' @())
  $fob = Scenario 'fragordboth' @('--enable', 'parser-error,syntax-error')
  Write-Host ("    walk order: fragorder inc={0} host={1}; fragordboth uses-host={2} code-host={3}" -f (ProgressAt 'fragorder' 'OrdUses.inc'), (ProgressAt 'fragorder' 'OrdHost.pas'), (ProgressAt 'fragordboth' 'AOrdBothUses.pas'), (ProgressAt 'fragordboth' 'COrdBothCode.pas')) -ForegroundColor DarkGray
  Check 'order (shape): fragorder walks the fragment before its host' (((ProgressAt 'fragorder' 'OrdHost.pas') -ge 0) -and ((ProgressAt 'fragorder' 'OrdUses.inc') -ge 0))
  Check 'order (shape): fragordboth walks the uses host before the code host' (((ProgressAt 'fragordboth' 'AOrdBothUses.pas') -ge 0) -and ((ProgressAt 'fragordboth' 'AOrdBothUses.pas') -lt (ProgressAt 'fragordboth' 'COrdBothCode.pas')))
  Check 'order: a fragment walked before its host has no DIAG parse error' ((IndexDiag 'fragorder' 'OrdUses.inc').Count -eq 0) "$((IndexDiag 'fragorder' 'OrdUses.inc').Count)"
  $op = @($script:indexOut['fragorder'] | Where-Object { $_ -match 'OrdUses\.inc ->' })
  Check 'order: ... and counts 0 errors on its progress line' (($op.Count -eq 1) -and ($op[0] -match ', 0 errors')) "$op"
  Check 'order control: an include walked before its CODE host keeps its DIAG parse error' ((IndexDiag 'fragordcode' 'OrdBroken.inc').Count -eq 1) "$((IndexDiag 'fragordcode' 'OrdBroken.inc').Count)"
  Check 'order: a fragment a LATER host includes as code keeps its DIAG parse error' ((IndexDiag 'fragordboth' 'BOrdBoth.inc').Count -eq 1) "$((IndexDiag 'fragordboth' 'BOrdBoth.inc').Count)"
  $fobe = @($fob | Where-Object { $_.rule -in @('parser-error', 'syntax-error') -and (Leaf $_) -eq 'BOrdBoth.inc' })
  Check 'order (agreement): lint-all reports that fragment too' ($fobe.Count -eq 2) "$($fobe.Count)"

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
