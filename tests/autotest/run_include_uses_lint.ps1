<#
  run_include_uses_lint.ps1 -- N-06 T5: a lint finding about a uses entry that
  lives in a {$I} include is reported on the HOST file at the include line,
  with the suffix " (in include <Name.inc>, line <n>)".

  Fixture tests\fixtures\includeuses\HostL.pas: own interface `uses
  NoSuchInlineUnit;` (line 9) and {$I HostL.Uses.inc} at line 16, whose
  `uses Leaf, NoSuchIncUnit;` puts Leaf on .inc line 2, NoSuchIncUnit on 3.
    a. used-unit-not-resolvable NoSuchIncUnit -> HostL.pas line 16, suffix
       "(in include HostL.Uses.inc, line 3)".
    b. POSITIVE CONTROL: NoSuchInlineUnit -> HostL.pas line 9, NO suffix.
    c. unused-unit-in-uses Leaf -> HostL.pas line 16, suffix "... line 2".
  Fixture tests\fixtures\cyclefix\incuses:
    d. lint IncB.pas circular-uses -> line 12 (the {$I}), not line 2.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-include-uses-lint-$PID"
)
$ErrorActionPreference = 'Stop'; $script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$inc = Join-Path $WorkDir 'incuses'; Copy-Item (Resolve-Path "$PSScriptRoot\..\fixtures\cyclefix\incuses").Path $inc -Recurse
$iu  = Join-Path $WorkDir 'includeuses'; Copy-Item (Resolve-Path "$PSScriptRoot\..\fixtures\includeuses").Path $iu -Recurse

function Run([string[]]$a) {
  Push-Location $WorkDir
  try { $o = & $Exe @a 2>$null | Out-String } finally { Pop-Location }
  return $o
}
function Findings([string]$json) { try { return ,@($json | ConvertFrom-Json) } catch { return ,@() } }

$db = Join-Path $WorkDir 'includeuses.sqlite'
$null = Run @('index', '--project', (Join-Path $iu 'IncUsesX.dproj'), '--db', $db, '--library-db', 'none')
$hostL = Join-Path $iu 'HostL.pas'

$fs = Findings (Run @('lint-all', '--db', $db, '--rule', 'used-unit-not-resolvable', '--json', '--library-db', 'none'))
$fi = @($fs | Where-Object { $_.message -match 'NoSuchIncUnit' })
$fn = @($fs | Where-Object { $_.message -match 'NoSuchInlineUnit' })
Check 'a: one used-unit-not-resolvable for NoSuchIncUnit' ($fi.Count -eq 1) "findings=$($fs.Count)"
$x = if ($fi.Count) { $fi[0] } else { [pscustomobject]@{} }
Check 'a: on HostL.pas at the {$I} line 16' (($x.file_path -eq $hostL) -and "$($x.start_line)" -eq '16') "got $($x.file_path):$($x.start_line)"
Check 'a: message suffix names the include and its line' ("$($x.message)".EndsWith(' (in include HostL.Uses.inc, line 3)')) "msg: $($x.message)"
$y = if ($fn.Count) { $fn[0] } else { [pscustomobject]@{} }
Check 'b: positive control: NoSuchInlineUnit on its own line 9' ("$($y.start_line)" -eq '9') "got $($y.start_line)"
Check 'b: positive control: an inline row carries no suffix' (($fn.Count -eq 1) -and ("$($y.message)" -notmatch 'in include')) "msg: $($y.message)"

$us = Findings (Run @('lint-all', '--db', $db, '--rule', 'unused-unit-in-uses', '--json', '--library-db', 'none'))
$ul = @($us | Where-Object { ($_.message -match "'Leaf'") -and ($_.file_path -eq $hostL) })
$z = if ($ul.Count) { $ul[0] } else { [pscustomobject]@{} }
Check 'c: unused-unit-in-uses Leaf on HostL.pas line 16' (($ul.Count -eq 1) -and "$($z.start_line)" -eq '16') "findings=$($us.Count) line=$($z.start_line)"
Check 'c: suffix names the include line 2' ("$($z.message)".EndsWith(' (in include HostL.Uses.inc, line 2)')) "msg: $($z.message)"

$db2 = Join-Path $WorkDir 'incuses.sqlite'
$null = Run @('index', '--project', (Join-Path $inc 'IncUses.dproj'), '--db', $db2, '--library-db', 'none')
$cf = Findings (Run @('lint', (Join-Path $inc 'IncB.pas'), '--db', $db2, '--rule', 'circular-uses', '--json', '--library-db', 'none'))
$c = if ($cf.Count) { $cf[0] } else { [pscustomobject]@{} }
Check 'd: lint IncB.pas circular-uses at the {$I} line 12' (($cf.Count -eq 1) -and "$($c.start_line)" -eq '12') "findings=$($cf.Count) line=$($c.start_line)"

if ($script:Failed) { Write-Host 'run_include_uses_lint: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_include_uses_lint: PASS' -ForegroundColor Green; exit 0