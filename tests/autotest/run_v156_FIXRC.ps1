<#
  run_v156_FIXRC.ps1 -- 1.56 fix lane FIXR-C (REV-1 finding 5): the indirect_edges pass after an
  INCREMENTAL index must give the rows a FULL index of the same sources gives.

  The pass (DRagLint.Index.IndirectCalls) is rebuilt whole on every dispatch pass; FIXR-C made its
  position lookup (FileRefAt) a per-position query instead of loading every ref of each file. This
  runner pins the behaviour that change must keep:

    V   vacuity: the fixture (tests\fixtures\v156-extc2) indexes and yields rows.
    I1  incremental == full: one unit gets a line inserted at its TOP (every line of it moves) and
        is re-indexed into the existing DB; the rows equal those of a fresh DB indexed from the same
        edited sources -- kind, caller, target, via, bind file / line / col, confidence, call name
        and call line, in table order.
    I2  a second unit is edited and re-indexed: still equal to a fresh full index.
    I3  nothing changed, index again: the rows stay.
  Positive control (PC): the edit MOVES rows -- the incremental rows differ from the rows before the
  edit by the shifted bind / call lines -- so an engine that left the table alone, or a comparison
  that cannot see a line, fails PC or I1.
  Not RED-able on the base: the change is behaviour-preserving (a speed-up); the base engine
  passes this runner too. Measured cost: C:\TEMP\claude\lanes\v156\FIXR-C\REPORT-FINAL.md.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_v156_FIXRC: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path $Exe)) { Write-Host "run_v156_FIXRC: no engine at $Exe" -ForegroundColor Red; exit 2 }
$fxSrc = Join-Path $repo 'tests\fixtures\v156-extc2'
$work  = Join-Path $env:TEMP ('dl-v156-fixrc-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null

$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name  $Detail" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}

# Every edge as ONE string, in table order. `sql --json` rows are POSITIONAL arrays. A failed
# query returns $null (never an empty list a comparison could pass on).
$edgeSql = @"
SELECT e.kind, COALESCE(c.qualified_name, ''), t.qualified_name, e.via_text, COALESCE(bf.path, ''),
       e.bind_line, e.bind_col, e.confidence, COALESCE(r.kind, ''), COALESCE(r.name_text, ''),
       COALESCE(r.start_line, 0), COALESCE(r.start_col, 0)
FROM indirect_edges e
JOIN symbols t ON t.id = e.target_symbol_id
LEFT JOIN symbols c ON c.id = e.caller_symbol_id
LEFT JOIN refs r ON r.id = e.ref_id
LEFT JOIN files bf ON bf.id = e.bind_file_id
ORDER BY e.id
"@ -replace "\r?\n", ' '
function Lane-Edges([string]$Db) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe sql --query $edgeSql --db $Db --json --limit 10000 2>$null }
  if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
  try { $j = ($raw -join "`n") | ConvertFrom-Json | ForEach-Object { $_ } } catch { return $null }
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($r in @($j.rows)) {
    $cells = @($r | ForEach-Object { "$_" })
    $cells[4] = [IO.Path]::GetFileName($cells[4])   # the two DBs index two copies of the fixture
    $out.Add($cells -join '|')
  }
  return ,$out.ToArray()
}
function Lane-Index([string]$Dir, [string]$Db, [string]$LogName) {
  $log = Join-Path $work $LogName
  & { $ErrorActionPreference = 'Continue'; & $Exe index $Dir --db $Db *> $log }
  return $LASTEXITCODE
}
# Inserts one comment line at the TOP of a unit: every line of the unit moves down by one.
function Shift-Unit([string]$Path) {
  $bytes = [IO.File]::ReadAllBytes($Path)
  [IO.File]::WriteAllBytes($Path, [Text.Encoding]::ASCII.GetBytes("{ fixrc: one line more }`r`n") + $bytes)
}
# A fresh DB indexed from a COPY of the incremental tree as it stands now.
function Full-Edges([string]$Tag) {
  $dir = Join-Path $work "full-$Tag"
  Copy-Item -Recurse $fxInc $dir
  $db = Join-Path $work "full-$Tag.sqlite"
  $rc = Lane-Index $dir $db "full-$Tag.log"
  if ($rc -ne 0) { return $null }
  return ,(Lane-Edges $db)
}
function Same-Rows($A, $B) {
  if (($null -eq $A) -or ($null -eq $B) -or ($A.Count -ne $B.Count) -or ($A.Count -eq 0)) { return $false }
  for ($i = 0; $i -lt $A.Count; $i++) { if ($A[$i] -cne $B[$i]) { return $false } }
  return $true
}
function Count-Of($Rows) { if ($null -eq $Rows) { return 'query failed' } else { return "$($Rows.Count)" } }

Write-Host "run_v156_FIXRC: engine $Exe" -ForegroundColor Cyan

$fxInc = Join-Path $work 'inc'; Copy-Item -Recurse $fxSrc $fxInc
$dbInc = Join-Path $work 'inc.sqlite'
$rc0   = Lane-Index $fxInc $dbInc 'inc-0.log'
$e0    = Lane-Edges $dbInc
Check 'V1 the fixture was indexed and indirect_edges holds rows' (($rc0 -eq 0) -and ($null -ne $e0) -and ($e0.Count -gt 0)) "(rc $rc0, rows $(Count-Of $e0))"

# ---- I1: one unit shifted, incremental vs full ---------------------------------------------
Shift-Unit (Join-Path $fxInc 'uIndA.pas')
$rc1 = Lane-Index $fxInc $dbInc 'inc-1.log'
$e1  = Lane-Edges $dbInc
$f1  = Full-Edges '1'
Check 'PC the edit moved rows: incremental rows differ from the rows before the edit, same count' (($null -ne $e0) -and ($null -ne $e1) -and ($e1.Count -eq $e0.Count) -and -not (Same-Rows $e0 $e1)) "($(Count-Of $e0) -> $(Count-Of $e1))"
Check 'I1 incremental index of one shifted unit == full index of the same sources' (($rc1 -eq 0) -and (Same-Rows $e1 $f1)) "(inc $(Count-Of $e1), full $(Count-Of $f1))"

# ---- I2: a second unit shifted ---------------------------------------------------------------
Shift-Unit (Join-Path $fxInc 'uIndForm.pas')
$rc2 = Lane-Index $fxInc $dbInc 'inc-2.log'
$e2  = Lane-Edges $dbInc
$f2  = Full-Edges '2'
Check 'I2 a second shifted unit: incremental == full' (($rc2 -eq 0) -and (Same-Rows $e2 $f2) -and -not (Same-Rows $e1 $e2)) "(inc $(Count-Of $e2), full $(Count-Of $f2))"

# ---- I3: nothing changed -----------------------------------------------------------------------
$rc3 = Lane-Index $fxInc $dbInc 'inc-3.log'
$e3  = Lane-Edges $dbInc
Check 'I3 an index run with nothing changed keeps the rows' (($rc3 -eq 0) -and (Same-Rows $e2 $e3)) "($(Count-Of $e3))"

if (-not $KeepScratch) { try { [IO.Directory]::Delete($work, $true) } catch { } } else { Write-Host "scratch: $work" }
Write-Host ("run_v156_FIXRC: {0} pass, {1} fail" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
exit $(if ($script:fail) { 1 } else { 0 })
