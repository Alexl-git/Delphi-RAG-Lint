<#
  run_cyclefix_dotted_unit.ps1 -- E-CYCLES-DOTTED-UNIT (wave 147). `cycles --fix --unit <name>` picks the
  circular group holding the unit. The name went through ChangeFileExt, so a dotted unit name lost its last
  segment (`Cf.Beta` -> `cf`) and the run refused "unit Cf.Beta is in no circular group" (exit 2). The --part all
  loop passes the group's FIRST stem as --unit to each child, so a group whose first stem is dotted failed too.

  Fixture tests\fixtures\cyclefix\includeclause with the include inlined (a mechanical 2-unit cycle) and CfBeta
  renamed to the dotted unit Cf.Beta (file, unit header, uses entries, .dpr, .dproj).
    a. --fix --unit Cf.Beta (dry run, JSON) selects the group: exit is not 2, no "in no circular group".
    b. --fix --unit Cf.Beta.pas (the .pas suffix is still dropped) selects it too.
    c. --fix --unit cfalpha (an undotted member) selects it: the fixture really is one circular group.
  POSITIVE CONTROL pc: --unit Cf (what the old code reduced Cf.Beta to) still refuses with "in no circular group",
    exit 2: the checks in a/b can fail.
  RED: engine 1.46.0-alpha fails a and b (exit 2, "unit Cf.Beta is in no circular group").
#>
[CmdletBinding()]
param(
  [string]$Exe     = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe") { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" } else { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }),
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-dotted-$PID"
)
$ErrorActionPreference = 'Stop'; $script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fix = (Resolve-Path "$PSScriptRoot\..\fixtures\cyclefix\includeclause").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$Ascii = [Text.Encoding]::ASCII
try {
  $root = Join-Path $WorkDir 'dotted'
  New-Item -ItemType Directory $root | Out-Null
  foreach ($n in 'CfAlpha.pas', 'IncludeClause.dpr', 'IncludeClause.dproj') {
    $t = [IO.File]::ReadAllText((Join-Path $Fix $n))
    if ($n -eq 'CfAlpha.pas') {
      $inc = [IO.File]::ReadAllText((Join-Path $Fix 'CfAlpha.Uses.inc')).TrimEnd("`r", "`n")
      $t = $t.Replace('{$I CfAlpha.Uses.inc}', $inc)
    }
    $t = [regex]::Replace($t, '\bCfBeta\b', 'Cf.Beta')
    [IO.File]::WriteAllText((Join-Path $root $n), $t, $Ascii)
  }
  $b = [regex]::Replace([IO.File]::ReadAllText((Join-Path $Fix 'CfBeta.pas')), '\bCfBeta\b', 'Cf.Beta')
  [IO.File]::WriteAllText((Join-Path $root 'Cf.Beta.pas'), $b, $Ascii)
  $dproj = Join-Path $root 'IncludeClause.dproj'
  Check 'fixture: the dotted unit is named in the .dpr and the .dproj' (([IO.File]::ReadAllText((Join-Path $root 'IncludeClause.dpr')) -match "Cf\.Beta in 'Cf\.Beta\.pas'") -and ([IO.File]::ReadAllText($dproj) -match 'Include="Cf\.Beta\.pas"')) ''

  $db = Join-Path $WorkDir 'dotted.sqlite'
  Push-Location $WorkDir
  try { & $Exe index --project $dproj --db $db --library-db none *> "$db.log" } finally { Pop-Location }
  Check 'fixture indexed' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

  function Invoke-Unit([string]$Unit) {
    Push-Location $WorkDir
    try { $o = & $Exe cycles --fix --project $dproj --db $db --unit $Unit --no-compile --format json --library-db none 2>&1 | Out-String; $rc = $LASTEXITCODE } finally { Pop-Location }
    return @{ Out = $o; Rc = $rc }
  }
  $NoGroup = 'is in no circular group'
  $short = { param($r) "rc=$($r.Rc) " + (($r.Out.Trim() -replace '\s+', ' ') -replace '^(.{0,200}).*$', '$1') }

  $c = Invoke-Unit 'cfalpha'
  Check 'c: --unit cfalpha selects the group (the fixture is circular)' (($c.Rc -ne 2) -and -not $c.Out.Contains($NoGroup)) (& $short $c)
  $a = Invoke-Unit 'Cf.Beta'
  Check 'a: --unit Cf.Beta selects the group' (($a.Rc -ne 2) -and -not $a.Out.Contains($NoGroup)) (& $short $a)
  Check 'a: the run is the same group as --unit cfalpha (same exit)' ($a.Rc -eq $c.Rc) "Cf.Beta rc=$($a.Rc) cfalpha rc=$($c.Rc)"
  $b2 = Invoke-Unit 'Cf.Beta.pas'
  Check 'b: --unit Cf.Beta.pas selects the group' (($b2.Rc -ne 2) -and -not $b2.Out.Contains($NoGroup)) (& $short $b2)
  $pc = Invoke-Unit 'Cf'
  Check 'pc: --unit Cf (no such unit) still refuses, exit 2' (($pc.Rc -eq 2) -and $pc.Out.Contains("unit Cf $NoGroup")) (& $short $pc)
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
if ($script:Failed) { Write-Host 'run_cyclefix_dotted_unit: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_cyclefix_dotted_unit: PASS' -ForegroundColor Green; exit 0
