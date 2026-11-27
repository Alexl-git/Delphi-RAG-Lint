# Acceptance runner for lane CHA-1 (1.56): `ask dependency-matrix` and `ask main-sequence` (G-40, gap plan S7).
#
# Usage: run_v156_CHA1.ps1 -Exe <drag-lint.exe> [-ExpectRed] [-Scratch <dir>]
#   -ExpectRed : the engine is the BASE engine; both questions must be refused as "unknown question"
#                (exit non-zero). Exit 0 = the RED is real. Without it the runner asserts the GREEN behaviour.
#
# GREEN assertions (fixture tests\fixtures\cha1: UA, UB, UC, UD, indexed into a DB under -Scratch):
#   dependency-matrix : the filled cells named in the .dot (TD tooltips "<A> uses <B>") are EXACTLY the unit-to-unit
#                       pairs of unit_uses read from the index by a separate query (set equality); library uses
#                       (System.SysUtils, System.Classes) are the one "lib" column: LibraryUnits = 2.
#   main-sequence     : Ca / Ce / I / A / D per unit equal the HAND-COMPUTED values below (tolerance 0.0005):
#        unit  Ca Ce   I      A     D      (UA uses UB,UC; UB uses UC; UD uses UA; UB has one abstract class of two;
#        UA    1  2  0.667  0.500  0.167    UA has interface IA + class TA; UC has two concrete classes; UD one)
#        UB    1  1  0.500  0.500  0.000
#        UC    2  0  0.000  0.000  1.000   <- the one unit off the main sequence (D > 0.5)
#        UD    0  1  1.000  0.000  0.000
#   POSITIVE CONTROLS (a check that cannot fail proves nothing):
#     PC-1 a variant fixture where UD also uses UC must give Edges = 5 and the same set equality again;
#     PC-2 the set comparer must REJECT the real pair set with one pair removed;
#     PC-3 a variant where UC's classes are interfaces must move UC to A = 1.000, D = 0.000 and OffSequence = 0;
#     PC-4 the metric comparer must REJECT the hand-computed table with UA's I changed by 0.1.
param(
  [Parameter(Mandatory)][string]$Exe,
  [switch]$ExpectRed,
  [string]$Scratch = ''
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $Scratch) { $Scratch = Join-Path $env:TEMP "cha1-run-$PID" }
[IO.Directory]::CreateDirectory($Scratch) | Out-Null
$fail = 0; $pass = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
  if ($ok) { $script:pass++; Write-Host "PASS  $name" } else { $script:fail++; Write-Host "FAIL  $name  $detail" -ForegroundColor Red }
}
function Run-Engine([string[]]$a) {
  $out = & $Exe @a 2>&1 | Out-String
  [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out }
}
function Index-Fixture([string]$dir, [string]$db) {
  if (Test-Path $db) { [IO.File]::Delete($db) }
  $r = Run-Engine @('index', $dir, '--db', $db)
  if ($r.Code -ne 0) { throw "index failed: $($r.Text)" }
}
function Ask([string]$q, [string]$db, [string]$out) {
  Run-Engine @('ask', $q, '--target', 'project', '--db', $db, '--plain', '--out-root', $out)
}
function Meta-Of([string]$out) {
  $m = Get-ChildItem $out -Recurse -Filter meta.json | Sort-Object LastWriteTime | Select-Object -Last 1
  if (-not $m) { return $null }
  Get-Content $m.FullName -Raw | ConvertFrom-Json
}
function Newest([string]$out, [string]$filter) {
  Get-ChildItem $out -Recurse -Filter $filter | Sort-Object LastWriteTime | Select-Object -Last 1
}
function Sql-Col0([string]$db, [string]$query) {
  $q = & $Exe sql --db $db --json --query $query 2>&1 | Out-String
  $j = ($q -replace '(?s)^.*?(\{)', '$1') | ConvertFrom-Json
  @($j.rows | ForEach-Object { $_[0] })
}
function Same-Set($a, $b) { (($a | Sort-Object) -join ';') -ceq (($b | Sort-Object) -join ';') }
function Matrix-Pairs([string]$out) {
  $dot = Newest $out '*.dot'
  if (-not $dot) { return @() }
  @([regex]::Matches((Get-Content $dot.FullName -Raw), 'TOOLTIP="(\w+) uses (\w+)"') | ForEach-Object { "$($_.Groups[1].Value)>$($_.Groups[2].Value)" })
}
function Index-Pairs([string]$db) {
  # unit-to-unit pairs among the indexed units, distinct, no self use (a query separate from the emitter's)
  Sql-Col0 $db "SELECT DISTINCT su.qualified_name || '>' || tu.qualified_name FROM unit_uses uu JOIN symbols su ON su.file_id = uu.file_id AND su.kind = 'unit' JOIN symbols tu ON tu.kind = 'unit' AND LOWER(tu.qualified_name) = LOWER(uu.unit_name) WHERE su.id <> tu.id"
}

$fx = Join-Path $repo 'tests\fixtures\cha1'
$db = Join-Path $Scratch 'cha1.sqlite'
Index-Fixture $fx $db

if ($ExpectRed) {
  foreach ($q in @('dependency-matrix', 'main-sequence')) {
    $r = Ask $q $db (Join-Path $Scratch 'red')
    Check "RED $q refused as unknown question" (($r.Code -ne 0) -and ($r.Text -match 'unknown question')) "exit=$($r.Code) $($r.Text)"
  }
  Write-Host "RED: $pass pass, $fail fail"; exit $(if ($fail) { 1 } else { 0 })
}

# ---- dependency-matrix ----
$o1 = Join-Path $Scratch 'dm1'
$r = Ask 'dependency-matrix' $db $o1
Check 'dependency-matrix exits 0' ($r.Code -eq 0) $r.Text
$m = Meta-Of $o1
$e = if ($m) { $m.emitter } else { $null }
$cells = Matrix-Pairs $o1
$real = Index-Pairs $db
Check "matrix cells equal unit_uses pairs ($($real -join ','))" ((Same-Set $cells $real) -and $real.Count -eq 4) "cells: $($cells -join ',')"
Check 'matrix: Units=4, Edges=4, LibraryUnits=2' ($e -and $e.Units -eq 4 -and $e.Edges -eq 4 -and $e.LibraryUnits -eq 2) ($e | ConvertTo-Json -Compress)
Check 'PC-2 the set comparer rejects the pair set with one pair removed' (-not (Same-Set $cells @($real | Select-Object -Skip 1)))

$fx2 = Join-Path $Scratch 'fx2'; [IO.Directory]::CreateDirectory($fx2) | Out-Null
Get-ChildItem $fx -Filter *.pas | ForEach-Object { Copy-Item $_.FullName (Join-Path $fx2 $_.Name) -Force }
$ud = [IO.File]::ReadAllText((Join-Path $fx2 'UD.pas')).Replace("  UA;", "  UA, UC;")
[IO.File]::WriteAllText((Join-Path $fx2 'UD.pas'), $ud, [Text.Encoding]::ASCII)
$db2 = Join-Path $Scratch 'cha1b.sqlite'
Index-Fixture $fx2 $db2
$o2 = Join-Path $Scratch 'dm2'
$r = Ask 'dependency-matrix' $db2 $o2
$m = Meta-Of $o2
Check 'PC-1 variant (UD also uses UC): Edges=5 and cells equal unit_uses again' ($m -and $m.emitter.Edges -eq 5 -and (Same-Set (Matrix-Pairs $o2) (Index-Pairs $db2))) ($m.emitter | ConvertTo-Json -Compress)

# ---- main-sequence ----
$want = @{
  UA = @{ Ca = 1; Ce = 2; I = 0.667; A = 0.5; D = 0.167 }
  UB = @{ Ca = 1; Ce = 1; I = 0.5; A = 0.5; D = 0.0 }
  UC = @{ Ca = 2; Ce = 0; I = 0.0; A = 0.0; D = 1.0 }
  UD = @{ Ca = 0; Ce = 1; I = 1.0; A = 0.0; D = 0.0 }
}
function Read-Metrics([string]$out) {
  $csv = Newest $out 'main_sequence_metrics.csv'
  $h = @{}
  if ($csv) {
    foreach ($row in (Import-Csv $csv.FullName)) {
      $h[$row.unit] = @{ Ca = [int]$row.Ca; Ce = [int]$row.Ce; I = [double]$row.I; A = [double]$row.A; D = [double]$row.D }
    }
  }
  $h
}
function Same-Metrics($got, $exp) {
  if ($got.Count -ne $exp.Count) { return $false }
  foreach ($u in $exp.Keys) {
    if (-not $got.ContainsKey($u)) { return $false }
    if ($got[$u].Ca -ne $exp[$u].Ca -or $got[$u].Ce -ne $exp[$u].Ce) { return $false }
    foreach ($k in 'I', 'A', 'D') { if ([math]::Abs($got[$u][$k] - $exp[$u][$k]) -gt 0.0005) { return $false } }
  }
  $true
}
$o3 = Join-Path $Scratch 'ms1'
$r = Ask 'main-sequence' $db $o3
Check 'main-sequence exits 0' ($r.Code -eq 0) $r.Text
$got = Read-Metrics $o3
Check 'main-sequence: Ca/Ce/I/A/D per unit equal the hand-computed table' (Same-Metrics $got $want) (($got.Keys | ForEach-Object { "$_=" + ($got[$_] | ConvertTo-Json -Compress) }) -join ' ')
$m = Meta-Of $o3
Check 'main-sequence: Units=4, OffSequence=1 (UC)' ($m -and $m.emitter.Units -eq 4 -and $m.emitter.OffSequence -eq 1) ($m.emitter | ConvertTo-Json -Compress)
$bad = @{}; foreach ($u in $want.Keys) { $bad[$u] = @{} + $want[$u] }; $bad.UA.I = 0.767
Check 'PC-4 the metric comparer rejects UA with I changed by 0.1' (-not (Same-Metrics $got $bad))

# PC-3: UC's two classes become interfaces
$fx3 = Join-Path $Scratch 'fx3'; [IO.Directory]::CreateDirectory($fx3) | Out-Null
Get-ChildItem $fx -Filter *.pas | ForEach-Object { Copy-Item $_.FullName (Join-Path $fx3 $_.Name) -Force }
$uc = [IO.File]::ReadAllText((Join-Path $fx3 'UC.pas')).Replace('TC1 = class(TObject)', 'TC1 = interface').Replace('TC2 = class(TObject)', 'TC2 = interface')
[IO.File]::WriteAllText((Join-Path $fx3 'UC.pas'), $uc, [Text.Encoding]::ASCII)
$db3 = Join-Path $Scratch 'cha1c.sqlite'
Index-Fixture $fx3 $db3
$o4 = Join-Path $Scratch 'ms2'
$r = Ask 'main-sequence' $db3 $o4
$g3 = Read-Metrics $o4
$m = Meta-Of $o4
Check 'PC-3 variant (UC types are interfaces): UC A=1.000 D=0.000, OffSequence=0' ($g3.ContainsKey('UC') -and [math]::Abs($g3.UC.A - 1.0) -lt 0.0005 -and $g3.UC.D -lt 0.0005 -and $m.emitter.OffSequence -eq 0) (($g3.UC | ConvertTo-Json -Compress) + ' ' + ($m.emitter | ConvertTo-Json -Compress))

Write-Host "CHA-1: $pass pass, $fail fail"
exit $(if ($fail) { 1 } else { 0 })
