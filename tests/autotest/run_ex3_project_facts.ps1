<#
  run_ex3_project_facts.ps1 -- wave 150 lane EX3: extractor / parser facts of a program and its project.

  Fixture tests\fixtures\ex3-facts-150 (folder index into a temp DB, then `sql --json`; rows are POSITIONAL):
    E2  program-level const / var of a .dpr are parented to a `program` symbol and qualified by it
        (Ex3App.COne / Ex3App.GRun). RED on 1.49.0-alpha base: no program symbol, parent_id NULL.
    E4  a HEADERLESS .dpr (no `program X;` line) gets its program symbol from the file name
        (Ex3Headerless); its var GBare is parented to it. RED on base: no program symbol.
    E3  project_settings holds the sibling .dproj's DCC_Namespace in document order, de-duplicated,
        the $(DCC_Namespace) macro dropped: System;Xml;Data;Winapi;System.Win;Vcl. RED on base: no table.
    E1  routine-local typed const CLocal: kind const, parent = LocalSum, read refs bound to it
        (FIXED-already on base: a pinned control, green on both).
    E7  `AObj is uEx3Types.TEx3Runner` (dotted is-rhs) emits a type_use in the shape of every other
        dotted type use: name_text TEx3Runner at its own span, the unit qualifier the text left of it.
        Binding is the resolver's: a dotted type_use stays symbol_id NULL today for a var type too
        (ar V: uEx3Types.TEx3Runner), so it is not asserted here. RED on base: no type_use at that span.
  POSITIVE CONTROLS: the unit symbols keep parent NULL and kind unit; the headerless program has no
  .dproj and so no project_settings row; the bare is-rhs keeps its bare name (a regression that
  qualified every is-rhs would fail it).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-ex3-facts-$PID"
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
$Fx  = (Resolve-Path (Join-Path $PSScriptRoot '..\fixtures\ex3-facts-150')).Path
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$Db = Join-Path $WorkDir 'ex3.sqlite'
if (Test-Path $Db) { [IO.File]::Delete($Db) }

$null = & $Exe index $Fx --db $Db 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: index exit $LASTEXITCODE" -ForegroundColor Red; exit 2 }

# One SELECT -> array of row arrays (sql --json rows are positional). A failing query (e.g. a table
# the base build does not create) returns an empty array, so the dependent checks FAIL, never pass.
function Rows([string]$q) {
  $raw = & $Exe sql --db $Db --query $q --json --limit 500 2>$null
  if ($LASTEXITCODE -ne 0) { return ,@() }
  $j = ($raw | Where-Object { $_ -notmatch '^\(loaded' }) -join "`n" | ConvertFrom-Json
  return ,@($j.rows)
}
function FileLike([string]$name) { "f.path LIKE '%\$name'" }

Write-Host "== EX3 project facts ($Exe)"

# E2: program symbol + parented program-level values
$p = Rows ("SELECT s.id, s.kind, s.parent_id FROM symbols s JOIN files f ON f.id=s.file_id WHERE " + (FileLike 'Ex3App.dpr') + " AND s.name='Ex3App'")
Check 'E2a Ex3App.dpr has a program symbol Ex3App (parent NULL)' (($p.Count -eq 1) -and ($p[0][1] -eq 'program') -and ($null -eq $p[0][2])) "rows=$($p | ConvertTo-Json -Compress)"
$progId = if ($p.Count -eq 1) { $p[0][0] } else { -1 }
foreach ($n in 'COne', 'CPlain', 'GRun', 'GCount') {
  $r = Rows ("SELECT s.parent_id, s.qualified_name FROM symbols s JOIN files f ON f.id=s.file_id WHERE " + (FileLike 'Ex3App.dpr') + " AND s.name='$n'")
  Check "E2b $n parented to the program, qualified Ex3App.$n" (($r.Count -eq 1) -and ($r[0][0] -eq $progId) -and ($r[0][1] -eq "Ex3App.$n")) "rows=$($r | ConvertTo-Json -Compress)"
}

# E4: headerless program
$h = Rows ("SELECT s.id, s.kind, s.start_line FROM symbols s JOIN files f ON f.id=s.file_id WHERE " + (FileLike 'Ex3Headerless.dpr') + " AND s.name='Ex3Headerless'")
Check 'E4a headerless .dpr gets program symbol Ex3Headerless from the file name' (($h.Count -eq 1) -and ($h[0][1] -eq 'program')) "rows=$($h | ConvertTo-Json -Compress)"
$hId = if ($h.Count -eq 1) { $h[0][0] } else { -1 }
$g = Rows ("SELECT s.parent_id FROM symbols s JOIN files f ON f.id=s.file_id WHERE " + (FileLike 'Ex3Headerless.dpr') + " AND s.name='GBare'")
Check 'E4b GBare parented to the headerless program' (($g.Count -eq 1) -and ($g[0][0] -eq $hId)) "rows=$($g | ConvertTo-Json -Compress)"

# E3: DCC_Namespace project fact
$ns = Rows ("SELECT ps.value FROM project_settings ps JOIN files f ON f.id=ps.file_id WHERE " + (FileLike 'Ex3App.dpr') + " AND ps.setting='DCC_Namespace' ORDER BY ps.ordinal")
$got = ($ns | ForEach-Object { $_[0] }) -join ';'
Check 'E3a project_settings DCC_Namespace = System;Xml;Data;Winapi;System.Win;Vcl (order, dedup, macro dropped)' ($got -ceq 'System;Xml;Data;Winapi;System.Win;Vcl') "got=[$got]"
$hn = Rows ("SELECT count(*) FROM project_settings ps JOIN files f ON f.id=ps.file_id WHERE " + (FileLike 'Ex3Headerless.dpr'))
Check 'E3b control: a .dpr without a .dproj stores no setting (table present, 0 rows)' (($hn.Count -eq 1) -and ($hn[0][0] -eq 0)) "rows=$($hn | ConvertTo-Json -Compress)"

# Controls: unit symbols unchanged
$u = Rows "SELECT count(*) FROM symbols WHERE kind='unit' AND parent_id IS NULL AND name IN ('uEx3Types','uEx3Local')"
Check 'C1 control: both unit symbols are kind unit, parent NULL' (($u.Count -eq 1) -and ($u[0][0] -eq 2)) "rows=$($u | ConvertTo-Json -Compress)"

# E1: routine-local typed const (pinned, FIXED-already)
$c = Rows ("SELECT s.id, s.kind, p.name FROM symbols s JOIN symbols p ON p.id=s.parent_id WHERE s.name='CLocal'")
Check 'E1a CLocal is a const symbol parented to LocalSum' (($c.Count -eq 1) -and ($c[0][1] -eq 'const') -and ($c[0][2] -eq 'LocalSum')) "rows=$($c | ConvertTo-Json -Compress)"
$cId = if ($c.Count -eq 1) { $c[0][0] } else { -1 }
$cr = Rows "SELECT count(*) FROM refs WHERE name_text='CLocal' AND kind='read' AND symbol_id=$cId"
Check 'E1b both CLocal reads are bound to it' (($cr.Count -eq 1) -and ($cr[0][0] -eq 2)) "rows=$($cr | ConvertTo-Json -Compress)"

# E7: dotted is-rhs emits a qualified type_use
$t = Rows ("SELECT r.name_text, r.symbol_id, r.start_col FROM refs r JOIN files f ON f.id=r.file_id WHERE " + (FileLike 'uEx3Local.pas') + " AND r.kind='type_use' AND r.start_line=23")
# Same shape as every dotted type use: the type's own name at its own span (col 31); the qualifier is the text
# left of it (`uEx3Types.` at cols 21-30), so a text check at the span sees the unit qualification.
$line23 = (Get-Content (Join-Path $Fx 'uEx3Local.pas'))[22]
Check 'E7a `is uEx3Types.TEx3Runner` emits ONE type_use TEx3Runner at col 31, qualifier left of it' (($t.Count -eq 1) -and ($t[0][0] -ceq 'TEx3Runner') -and ($t[0][2] -eq 31) -and ($line23.Substring(20, 10) -ceq 'uEx3Types.')) "rows=$($t | ConvertTo-Json -Compress)"

$b = Rows ("SELECT r.name_text FROM refs r JOIN files f ON f.id=r.file_id WHERE " + (FileLike 'uEx3Local.pas') + " AND r.kind='type_use' AND r.start_line=24")
Check 'E7c control: bare `is TEx3Base` keeps its bare name_text' (($b.Count -eq 1) -and ($b[0][0] -ceq 'TEx3Base')) "rows=$($b | ConvertTo-Json -Compress)"

Write-Host ("== {0} passed, {1} failed" -f $script:Passed, $script:Failed)
try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "  (left $WorkDir)" }
exit ([int]($script:Failed -gt 0))
