<#
  run_v1511_CLI_b03_deadcode_used_unit.ps1 -- lane v1511 CLI, item B03 (card C10).
  find-deadcode listed a unit as a dead-code candidate although a program or library
  names it in its uses clause: nothing references a unit by NAME (refs.name_text), so
  every unit looked unreferenced. A unit named in any uses clause (unit_uses) is not dead.
  Fixture: tests\fixtures\t2-library-root-150 (library T2Lib uses uT2LibUnit), a program
  P2 over the same unit, and an orphan unit nobody uses (positive control: still listed).
  Usage: pwsh -File tests\autotest\run_v1511_CLI_b03_deadcode_used_unit.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = (Join-Path $PSScriptRoot '..\..\src\cli\Win64\Debug\drag-lint.exe'))
$ErrorActionPreference = 'Stop'
$exePath = (Resolve-Path $Exe).Path
$fx = Join-Path $PSScriptRoot '..\fixtures\t2-library-root-150'
$scratch = Join-Path $env:TEMP ("v1511_cli_b03_" + $PID)
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name $Detail" -ForegroundColor Red; $script:fail++ }
}
try {
  $lib = Join-Path $scratch 'lib'
  New-Item -ItemType Directory -Path $lib -Force | Out-Null
  Copy-Item (Join-Path $fx '*') $lib -Force
  [IO.File]::WriteAllText((Join-Path $lib 'uOrphanUnit.pas'), "unit uOrphanUnit;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`nend.`r`n")
  $dbL = Join-Path $scratch 'lib.sqlite'
  & $exePath index $lib --db $dbL 2>&1 | Out-Null
  $outL = (& $exePath find-deadcode --db $dbL 2>&1 | Out-String)
  Check 'library: uT2LibUnit (in T2Lib uses) is not a dead-code candidate' ($outL -notmatch '(?m)^uT2LibUnit\s+\[unit\]') $outL
  Check 'library: positive control -- the orphan unit IS listed' ($outL -match '(?m)^uOrphanUnit\s+\[unit\]') $outL
  Check 'library: the library root T2Lib is not listed' ($outL -notmatch '(?m)^T2Lib\s+\[') $outL

  $prog = Join-Path $scratch 'prog'
  New-Item -ItemType Directory -Path $prog -Force | Out-Null
  Copy-Item (Join-Path $fx 'uT2LibUnit.pas') $prog -Force
  [IO.File]::WriteAllText((Join-Path $prog 'P2.dpr'), "program P2;`r`n`r`nuses`r`n  uT2LibUnit in 'uT2LibUnit.pas';`r`n`r`nbegin`r`nend.`r`n")
  $dbP = Join-Path $scratch 'prog.sqlite'
  & $exePath index $prog --db $dbP 2>&1 | Out-Null
  $outP = (& $exePath find-deadcode --db $dbP 2>&1 | Out-String)
  Check 'program: uT2LibUnit (in P2 uses) is not a dead-code candidate' ($outP -notmatch '(?m)^uT2LibUnit\s+\[unit\]') $outP
  Check 'program: T2Twice (never called) is still listed' ($outP -match '(?m)^uT2LibUnit\.T2Twice\s+\[function\]') $outP

  $outK = (& $exePath find-deadcode --db $dbL --kind unit 2>&1 | Out-String)
  Check '--kind unit: only the orphan unit' (($outK -match '(?m)^uOrphanUnit\s+\[unit\]') -and ($outK -match 'Found 1 dead-code')) $outK
} finally {
  if (Test-Path -LiteralPath $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
if ($fail -gt 0) { Write-Host "FAIL ($fail)" -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
