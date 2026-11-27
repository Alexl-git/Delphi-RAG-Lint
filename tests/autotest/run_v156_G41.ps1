# Acceptance runner for lane G41 (1.56): `ask hotspots` (G-41, gap plan S7), the size / complexity treemap.
#
# Usage: run_v156_G41.ps1 -Exe <drag-lint.exe> [-ExpectRed] [-Scratch <dir>]
#   -ExpectRed : the engine is the BASE engine; the question must be refused as "unknown question"
#                (exit non-zero). Exit 0 = the RED is real. Without it the runner asserts the GREEN behaviour.
#
# GREEN assertions (fixture tests\fixtures\g41, indexed into a DB under -Scratch):
#   HA.pas: 40 lines, one routine with 24 ifs  -> cyclomatic 25 -> fill #FBD9B5 (high), the hotspot
#   HC.pas: 27 lines, one routine with 11 ifs  -> cyclomatic 12 -> fill #FFF4CC (moderate)
#   HB.pas: 18 lines, one routine with  2 ifs  -> cyclomatic  3 -> fill #E2F1EF (low)
#   Lines are read from the files by the runner (not from the index); the rectangle areas (width x height in
#   the .dot) are ordered like the sizes and proportional to them within 15 percent (a fixed gap shaves the small ones).
#   Units=3, Hot=1, Findings='not stored', the dot says "no findings in this DB"; --cap 2 keeps the two
#   largest units and reports Hidden=1.
#   POSITIVE CONTROLS:
#     PC-1 variant fixture (HA: 2 ifs, HC: 30 ifs) moves the hotspot: HC cyclomatic 31 -> fill #FBD9B5 and the
#          csv's hottest-cyclomatic unit is HC, HA falls to the low fill;
#     PC-2 the pin comparer must REJECT the real table with HA's fill changed;
#     PC-3 a variant where HB grows to 200 lines must change the area order (HB first).
param(
  [Parameter(Mandatory)][string]$Exe,
  [switch]$ExpectRed,
  [string]$Scratch = ''
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $Scratch) { $Scratch = Join-Path $env:TEMP "g41-run-$PID" }
[IO.Directory]::CreateDirectory($Scratch) | Out-Null
$fail = 0; $pass = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
  if ($ok) { $script:pass++; Write-Host "PASS  $name" } else { $script:fail++; Write-Host "FAIL  $name  $detail" -ForegroundColor Red }
}
function Run-Engine([string[]]$a) {
  $out = & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } } | Out-String
  [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out }
}
function Index-Fixture([string]$dir, [string]$db) {
  if (Test-Path $db) { [IO.File]::Delete($db) }
  $r = Run-Engine @('index', $dir, '--db', $db)
  if ($r.Code -ne 0) { throw "index failed: $($r.Text)" }
}
function Ask([string]$db, [string]$out, [string[]]$extra = @()) {
  Run-Engine (@('ask', 'hotspots', '--target', 'project', '--db', $db, '--plain', '--out-root', $out) + $extra)
}
function Newest([string]$out, [string]$filter) {
  Get-ChildItem $out -Recurse -Filter $filter | Sort-Object LastWriteTime | Select-Object -Last 1
}
function Meta-Of([string]$out) {
  $m = Newest $out 'meta.json'
  if (-not $m) { return $null }
  Get-Content $m.FullName -Raw | ConvertFrom-Json | ForEach-Object { $_ }
}
# unit -> @{ Lines; Cc; Fill; Area } read from the .dot
function Read-Tiles([string]$out) {
  $h = @{}
  $dot = Newest $out '*.dot'
  if (-not $dot) { return $h }
  foreach ($m in [regex]::Matches((Get-Content $dot.FullName -Raw), '(?m)^\s*u\d+ \[label="(\w+)\\n(\d+) lines  cc (\d+)", fillcolor="(#\w+)", width=([\d.]+), height=([\d.]+)')) {
    $g = $m.Groups
    $h[$g[1].Value] = @{ Lines = [int]$g[2].Value; Cc = [int]$g[3].Value; Fill = $g[4].Value; Area = [double]$g[5].Value * [double]$g[6].Value }
  }
  $h
}
function Same-Pins($got, $exp) {
  if ($got.Count -ne $exp.Count) { return $false }
  foreach ($u in $exp.Keys) {
    if (-not $got.ContainsKey($u)) { return $false }
    foreach ($k in 'Lines', 'Cc', 'Fill') { if ($got[$u][$k] -ne $exp[$u][$k]) { return $false } }
  }
  $true
}
function Area-Order($t) { (($t.Keys | Sort-Object { -$t[$_].Area }) -join '>') }
function File-Lines([string]$path) { @([IO.File]::ReadAllLines($path)).Count }

$fx = Join-Path $repo 'tests\fixtures\g41'
$db = Join-Path $Scratch 'g41.sqlite'
Index-Fixture $fx $db

if ($ExpectRed) {
  $r = Ask $db (Join-Path $Scratch 'red')
  Check 'RED hotspots refused as unknown question' (($r.Code -ne 0) -and ($r.Text -match 'unknown question')) "exit=$($r.Code) $($r.Text)"
  Write-Host "RED: $pass pass, $fail fail"; exit $(if ($fail) { 1 } else { 0 })
}

$want = @{
  HA = @{ Lines = 40; Cc = 25; Fill = '#FBD9B5' }
  HC = @{ Lines = 27; Cc = 12; Fill = '#FFF4CC' }
  HB = @{ Lines = 18; Cc = 3; Fill = '#E2F1EF' }
}
foreach ($u in $want.Keys) {
  Check "fixture $u is $($want[$u].Lines) lines on disk" ((File-Lines (Join-Path $fx "$u.pas")) -eq $want[$u].Lines)
}
$o1 = Join-Path $Scratch 'h1'
$r = Ask $db $o1
Check 'hotspots exits 0' ($r.Code -eq 0) $r.Text
$got = Read-Tiles $o1
Check 'sizes, complexities and fills equal the pinned table' (Same-Pins $got $want) (($got.Keys | ForEach-Object { "$_=" + ($got[$_] | ConvertTo-Json -Compress) }) -join ' ')
Check 'area order follows the sizes: HA>HC>HB' ((Area-Order $got) -eq 'HA>HC>HB') (Area-Order $got)
$sum = ($got.Values | ForEach-Object { $_.Area } | Measure-Object -Sum).Sum
$prop = $true
foreach ($u in $want.Keys) { if ($got.ContainsKey($u)) { $share = $got[$u].Area / $sum; $exp = $want[$u].Lines / 85.0; if ([math]::Abs($share - $exp) / $exp -gt 0.15) { $prop = $false } } }
Check 'areas are proportional to the line counts within 15 percent' $prop
$m = Meta-Of $o1
$e = if ($m) { $m.emitter } else { $null }
Check 'meta: Units=3, Hot=1, Hidden=0, Findings=not stored' ($e -and $e.Units -eq 3 -and $e.Hot -eq 1 -and $e.Hidden -eq 0 -and $e.Findings -eq 'not stored') ($e | ConvertTo-Json -Compress)
Check 'the chart states that no findings are stored' ((Get-Content (Newest $o1 '*.dot').FullName -Raw) -match 'no findings in this DB')
$csv = Import-Csv (Newest $o1 'hotspots_metrics.csv').FullName
$ha = $csv | Where-Object { $_.unit -eq 'HA' }
Check 'csv: HA hottest routine WorkHA with cyclomatic 25' ($ha -and $ha.hottest_routine -match 'WorkHA' -and [int]$ha.hottest_cyclomatic -eq 25 -and [int]$ha.cyclomatic_max -eq 25) ($ha | ConvertTo-Json -Compress)

$o2 = Join-Path $Scratch 'h2'
$r = Ask $db $o2 @('--cap', '2')
$m2 = Meta-Of $o2
Check '--cap 2 draws the two largest units (HA, HC), Hidden=1' ($r.Code -eq 0 -and $m2.emitter.Units -eq 2 -and $m2.emitter.Hidden -eq 1 -and (Area-Order (Read-Tiles $o2)) -eq 'HA>HC') ($m2.emitter | ConvertTo-Json -Compress)

# PC-2: the comparer must reject a wrong table
$bad = @{}; foreach ($u in $want.Keys) { $bad[$u] = @{} + $want[$u] }; $bad.HA.Fill = '#E2F1EF'
Check 'PC-2 the pin comparer rejects the table with HA fill changed' (-not (Same-Pins $got $bad))

# PC-1: the hotspot moves
function New-Variant([string]$name, [scriptblock]$edit) {
  $d = Join-Path $Scratch $name; [IO.Directory]::CreateDirectory($d) | Out-Null
  Get-ChildItem $fx -Filter *.pas | ForEach-Object { Copy-Item $_.FullName (Join-Path $d $_.Name) -Force }
  & $edit $d
  $d
}
function Gen-Unit([string]$dir, [string]$name, [int]$ifs, [int]$pad) {
  $L = @("unit $name;", '', 'interface', '', "procedure Work$name(A: Integer);", '', 'implementation', '', "procedure Work$name(A: Integer);", 'var', '  N: Integer;', 'begin', '  N:= 0;')
  for ($i = 1; $i -le $ifs; $i++) { $L += "  if A = $i then Inc(N);" }
  $L += 'end;'
  for ($i = 1; $i -le $pad; $i++) { $L += "// pad $i" }
  $L += @('', 'end.')
  [IO.File]::WriteAllText((Join-Path $dir "$name.pas"), (($L -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
}
$v1 = New-Variant 'fxv1' { param($d) Gen-Unit $d 'HA' 2 21; Gen-Unit $d 'HC' 30 0 }
$dbv1 = Join-Path $Scratch 'g41v1.sqlite'; Index-Fixture $v1 $dbv1
$o3 = Join-Path $Scratch 'h3'; $null = Ask $dbv1 $o3
$t3 = Read-Tiles $o3
$csv3 = Import-Csv (Newest $o3 'hotspots_metrics.csv').FullName | Sort-Object { [int]$_.cyclomatic_max } -Descending
Check 'PC-1 variant (HA 2 ifs, HC 30 ifs): the hottest unit is HC (cc 31, high fill), HA falls to the low fill' ($t3.HC.Cc -eq 31 -and $t3.HC.Fill -eq '#FBD9B5' -and $t3.HA.Fill -eq '#E2F1EF' -and $csv3[0].unit -eq 'HC') (($t3.Keys | ForEach-Object { "$_=" + ($t3[$_] | ConvertTo-Json -Compress) }) -join ' ')

# PC-3: size drives area
$v2 = New-Variant 'fxv2' { param($d) Gen-Unit $d 'HB' 2 182 }
$dbv2 = Join-Path $Scratch 'g41v2.sqlite'; Index-Fixture $v2 $dbv2
$o4 = Join-Path $Scratch 'h4'; $null = Ask $dbv2 $o4
Check 'PC-3 variant (HB grows to 200 lines): HB has the largest area' ((Area-Order (Read-Tiles $o4)) -match '^HB>') (Area-Order (Read-Tiles $o4))

Write-Host "G41: $pass pass, $fail fail"
exit $(if ($fail) { 1 } else { 0 })