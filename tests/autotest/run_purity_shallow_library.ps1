<#
  run_purity_shallow_library.ps1 -- 146 g1 (wave 148 lane PB, 149 resolver bump):
  a routine in a SHALLOW-parsed file (library mode / --shallow: call refs only,
  no read/write/member-access refs) must NOT be stored effect-free. The purity
  stage judges a body by its usage refs; with none recorded, an `FActive:= True`
  body looked empty and was proven (TDataSet.Open in library-Win32.sqlite).

  Indexes tests\autotest\fixtures\purity-shallow twice into scratch DBs:
    DEEP    -- POSITIVE CONTROL: the writers carry their real summaries (s / g)
               and the readers stay proven, so the fixture does encode effects
               and the shallow rule does not fire on a deep file.
    SHALLOW -- every routine with a body is effect_free = 0, summary '?', with
               the witness 'no usage facts (shallow parse)'.
  RED on 1.46.0-alpha: the shallow writers are effect_free = 1.
  Run from any CWD under pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_purity_shallow_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe      = (Resolve-Path $Exe).Path
$fixtures = (Resolve-Path "$PSScriptRoot\fixtures\purity-shallow").Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

function Lane-IndexMode([string]$mode) {
  $src = Join-Path $WorkDir "src_$mode"
  New-Item -ItemType Directory $src | Out-Null
  Copy-Item (Join-Path $fixtures '*.pas') $src
  $db = Join-Path $WorkDir "$mode.sqlite"
  Push-Location C:\TEMP
  try { $o = @(& $Exe index $src --db $db "--$mode" 2>&1 | ForEach-Object { "$_" }) } finally { Pop-Location }
  return [pscustomobject]@{ Db = $db; Out = $o }
}
function Lane-Verdict([string]$db, [string]$qname) {
  $t = (& $Exe sql --db $db --format text --query "SELECT ifnull(f.effect_free,-1), '[' || ifnull(f.effect_summary,'') || ']', '[' || ifnull(f.effect_witness,'') || ']' FROM symbols s JOIN symbol_facts f ON f.symbol_id=s.id WHERE s.qualified_name='$qname'" 2>&1) -join "`n"
  $m = [regex]::Match($t, '(?m)^\s*(-?\d+)\s+\[(.*?)\]\s+\[(.*)\]\s*$')
  if (-not $m.Success) { return [pscustomobject]@{ ef = -2; es = '<norow>'; ew = '<norow>' } }
  return [pscustomobject]@{ ef = [int]$m.Groups[1].Value; es = $m.Groups[2].Value; ew = $m.Groups[3].Value }
}
function Lane-UsageRefs([string]$db) {
  $t = (& $Exe sql --db $db --format text --query "SELECT 'n=' || COUNT(*) FROM refs WHERE kind IN ('read','write','member-access')" 2>&1) -join "`n"
  $m = [regex]::Match($t, 'n=(\d+)')
  if ($m.Success) { return [int]$m.Groups[1].Value } else { return -1 }
}

$deep    = Lane-IndexMode 'deep'
$shallow = Lane-IndexMode 'shallow'
Check '0. both modes indexed' ((Test-Path $deep.Db) -and (Test-Path $shallow.Db)) ''
$nd = Lane-UsageRefs $deep.Db
$ns = Lane-UsageRefs $shallow.Db
Check '0. the deep index holds usage refs, the shallow one none (the modes differ as assumed)' (($nd -gt 0) -and ($ns -eq 0)) "deep=$nd shallow=$ns"

Write-Host 'DEEP (positive control)' -ForegroundColor Cyan
$v = Lane-Verdict $deep.Db 'uShallow.TGate.Open'
Check 'D1. TGate.Open writes its own field: not proven, summary s' (($v.ef -eq 0) -and ($v.es -match 's')) "$($v.ef) $($v.es) | $($v.ew)"
$v = Lane-Verdict $deep.Db 'uShallow.SetFlag'
Check 'D2. SetFlag writes a global: not proven, summary g' (($v.ef -eq 0) -and ($v.es -match 'g')) "$($v.ef) $($v.es) | $($v.ew)"
$v = Lane-Verdict $deep.Db 'uShallow.Twice'
Check 'D3. Twice is proven in a deep file (the shallow rule does not fire)' ($v.ef -eq 1) "$($v.ef) $($v.es) | $($v.ew)"
$v = Lane-Verdict $deep.Db 'uShallow.TGate.IsOpen'
Check 'D4. TGate.IsOpen (reads only) is proven in a deep file' ($v.ef -eq 1) "$($v.ef) $($v.es) | $($v.ew)"

Write-Host 'SHALLOW (the fix)' -ForegroundColor Cyan
$v = Lane-Verdict $shallow.Db 'uShallow.TGate.Open'
Check 'S0. TGate.Open (field write seen from the facts) keeps s and its witness, and gains ?' (($v.ef -eq 0) -and ($v.es -match 's') -and ($v.es -match '\?') -and ($v.ew -eq 'writes field FActive')) "$($v.ef) $($v.es) | $($v.ew)"
foreach ($q in 'uShallow.SetFlag', 'uShallow.Twice', 'uShallow.TGate.IsOpen') {
  $v = Lane-Verdict $shallow.Db $q
  Check "S. $q in a shallow file is ? with the shallow witness" (($v.ef -eq 0) -and ($v.es -eq '?') -and ($v.ew -eq 'no usage facts (shallow parse)')) "$($v.ef) $($v.es) | $($v.ew)"
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
