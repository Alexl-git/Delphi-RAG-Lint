<#
  run_unit_uses_origin_columns.ps1 -- N-06 T3: unit_uses.origin_path and
  unit_uses.include_line (additive, NULL = an entry in the unit's own text).

  1. A FRESH index of tests\fixtures\cyclefix\incuses has both columns.
  2. Every row of IncA.pas (inline uses only) reads origin_path NULL and
     include_line NULL; POSITIVE CONTROL: IncA really has its IncB row.
  3. MIGRATION: a DB built by an OLD engine (-OldExe, optional) is still READ by
     the new engine before any migration, then gains both columns and
     idx_unit_uses_origin when the new engine reindexes it.
  The round trip of a NON-NULL origin is asserted by run_include_uses.ps1 (T4),
  the first writer of the columns.
#>
[CmdletBinding()]
param(
  [string]$Exe    = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$OldExe = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-uses-origin-$PID"
)
$ErrorActionPreference = 'Stop'; $script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$src = (Resolve-Path "$PSScriptRoot\..\fixtures\cyclefix\incuses").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$fx = Join-Path $WorkDir 'incuses'
Copy-Item $src $fx -Recurse

function Index([string]$exe, [string]$db) {
  Push-Location $WorkDir
  try { & $exe index --project "$fx\IncUses.dproj" --db $db *> "$db.log" } finally { Pop-Location }
  return $LASTEXITCODE
}
function Sql([string]$db, [string]$q) {
  Push-Location $WorkDir
  try { $j = & $Exe sql --db $db --query $q --json 2>$null | Out-String } finally { Pop-Location }
  try { $o = $j | ConvertFrom-Json } catch { $o = $null }
  if ($null -eq $o -or $null -eq $o.columns) { return ,@() }
  $names = @($o.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
  $rows = @()
  foreach ($r in @($o.rows)) { $h = [ordered]@{}; for ($k = 0; $k -lt $names.Count; $k++) { $h[$names[$k]] = $r[$k] }; $rows += [pscustomobject]$h }
  return ,$rows
}
function HasColumns([string]$db) {
  Push-Location $WorkDir
  try { $j = & $Exe schema --db $db --format json 2>$null | Out-String } finally { Pop-Location }
  $t = ($j | ConvertFrom-Json).tables | Where-Object { $_.name -eq 'unit_uses' }
  return @($t.columns | Where-Object { $_.name -in @('origin_path', 'include_line') }).Count
}

$db = Join-Path $WorkDir 'fresh.sqlite'
$rc = Index $Exe $db
Check 'fresh index exits 0' ($rc -eq 0) "rc=$rc"
$n = HasColumns $db
Check 'fresh unit_uses has origin_path + include_line' ($n -eq 2) "got $n"
$a = Sql $db "SELECT u.unit_name, u.origin_path, u.include_line FROM unit_uses u JOIN files f ON f.id = u.file_id WHERE f.path LIKE '%IncA.pas'"
Check 'positive control: IncA.pas has its IncB row' (@($a | Where-Object { $_.unit_name -eq 'IncB' }).Count -eq 1) "rows=$($a.Count)"
Check 'IncA.pas inline rows: origin_path NULL' (@($a | Where-Object { $null -ne $_.origin_path }).Count -eq 0)
Check 'IncA.pas inline rows: include_line NULL' (@($a | Where-Object { $null -ne $_.include_line }).Count -eq 0)

if ($OldExe -ne '') {
  $old = Join-Path $WorkDir 'old.sqlite'
  $null = Index ((Resolve-Path $OldExe).Path) $old
  $before = HasColumns $old
  Check 'control: the OLD engine DB lacks the columns' ($before -eq 0) "got $before"
  # A READ-ONLY verb never runs Migrate: the new engine must still read the
  # old shape (FindUsersOfUnit names no column the DB lacks).
  Push-Location $WorkDir
  try { $uu = & $Exe query unit-usage --unit IncB --db $old 2>&1 | Out-String; $uuRc = $LASTEXITCODE } finally { Pop-Location }
  Check 'new engine reads the OLD DB read-only (unit-usage exits 0, names IncA)' (($uuRc -eq 0) -and ($uu -match 'IncA')) "rc=$uuRc"
  $rc2 = Index $Exe $old
  Check 'new engine reindexes the old DB (exit 0)' ($rc2 -eq 0) "rc=$rc2"
  $after = HasColumns $old
  Check 'migration added origin_path + include_line' ($after -eq 2) "got $after"
  $ix = Sql $old "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_unit_uses_origin'"
  Check 'migration added idx_unit_uses_origin' ($ix.Count -eq 1)
}

if ($script:Failed) { Write-Host 'run_unit_uses_origin_columns: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_unit_uses_origin_columns: PASS' -ForegroundColor Green; exit 0