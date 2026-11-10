<#
  run_library_root_symbol.ps1 -- wave 150 lane T2 (TAILS G3, EX3-a): a `library X;` .dpr root.

  Fixture tests\fixtures\t2-library-root-150 (folder index into a temp DB, then `sql --json`; rows are POSITIONAL):
    L1  T2Lib.dpr has a root symbol T2Lib, kind program (no skLibrary kind exists), parent NULL.
    L2  its top-level const / var / function (CLibVer, GLibCount, LibAdd) are parented to it and
        qualified by it (T2Lib.CLibVer), the shape EX3 gave program / package roots.
    L3  its uses clause is recorded in unit_uses (section program) -- the base recorded NO row.
  RED on 1.49.0-alpha base: no T2Lib symbol, the three decls parent_id NULL, unit_uses empty.
  POSITIVE CONTROLS: the unit symbol uT2LibUnit keeps kind unit / parent NULL; a param keeps its
  routine parent (LibAdd.A -> T2Lib.LibAdd.A).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-t2-libroot-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = 0; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:Failed++; if ($d) { Write-Host "      $d" -ForegroundColor DarkGray } }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx  = (Resolve-Path (Join-Path $PSScriptRoot '..\fixtures\t2-library-root-150')).Path
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$Db = Join-Path $WorkDir 'libroot.sqlite'
if (Test-Path $Db) { [IO.File]::Delete($Db) }

$null = & $Exe index $Fx --db $Db 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: index exit $LASTEXITCODE" -ForegroundColor Red; exit 2 }

function Rows([string]$q) {
  $raw = & $Exe sql --db $Db --query $q --json --limit 500 2>$null
  if ($LASTEXITCODE -ne 0) { return ,@() }
  $j = ($raw | Where-Object { $_ -notmatch '^\(loaded' }) -join "`n" | ConvertFrom-Json
  return ,@($j.rows)
}
$InLib = "f.path LIKE '%\T2Lib.dpr'"

Write-Host "== T2 library root symbol ($Exe)"

$p = Rows ("SELECT s.id, s.kind, s.parent_id FROM symbols s JOIN files f ON f.id=s.file_id WHERE $InLib AND s.name='T2Lib'")
Check 'L1 T2Lib.dpr has a root symbol T2Lib (kind program, parent NULL)' (($p.Count -eq 1) -and ($p[0][1] -eq 'program') -and ($null -eq $p[0][2])) "rows=$($p | ConvertTo-Json -Compress)"
$libId = if ($p.Count -eq 1) { $p[0][0] } else { -1 }
foreach ($n in 'CLibVer', 'GLibCount', 'LibAdd') {
  $r = Rows ("SELECT s.parent_id, s.qualified_name FROM symbols s JOIN files f ON f.id=s.file_id WHERE $InLib AND s.name='$n'")
  Check "L2 $n parented to the library root, qualified T2Lib.$n" (($r.Count -eq 1) -and ($r[0][0] -eq $libId) -and ($r[0][1] -ceq "T2Lib.$n")) "rows=$($r | ConvertTo-Json -Compress)"
}
$u = Rows ("SELECT uu.unit_name, uu.section FROM unit_uses uu JOIN files f ON f.id=uu.file_id WHERE $InLib")
Check 'L3 the library uses clause is recorded: uT2LibUnit, section program' (($u.Count -eq 1) -and ($u[0][0] -ceq 'uT2LibUnit') -and ($u[0][1] -eq 'program')) "rows=$($u | ConvertTo-Json -Compress)"

$c = Rows "SELECT count(*) FROM symbols WHERE kind='unit' AND parent_id IS NULL AND name='uT2LibUnit'"
Check 'C1 control: uT2LibUnit stays kind unit, parent NULL' (($c.Count -eq 1) -and ($c[0][0] -eq 1)) "rows=$($c | ConvertTo-Json -Compress)"
$a = Rows ("SELECT ps.name FROM symbols s JOIN symbols ps ON ps.id=s.parent_id JOIN files f ON f.id=s.file_id WHERE $InLib AND s.kind='param' AND s.name='A'")
Check 'C2 control: param A keeps its routine parent LibAdd' (($a.Count -eq 1) -and ($a[0][0] -ceq 'LibAdd')) "rows=$($a | ConvertTo-Json -Compress)"

Write-Host ("== {0} passed, {1} failed" -f $script:Passed, $script:Failed)
try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "  (left $WorkDir)" }
exit ([int]($script:Failed -gt 0))
