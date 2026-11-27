# Acceptance runner for lane G47 (1.56): `ask architecture-delta` (G-47), a picture of what changed between two indexes.
#
# Usage: run_v156_G47.ps1 -Exe <drag-lint.exe> [-ExpectRed] [-Scratch <dir>]
#   -ExpectRed : the engine is the BASE engine; the question must be refused as "unknown question".
#
# Fixtures tests\fixtures\g47\{before,after}, each indexed into its own DB under -Scratch (--db after, --counterpart-db before):
#   before: A->B, B->C, D->C, E->D       (units A B C D E)
#   after : A->B, B->C, C->A, F->A       (units A B C D F)
#   pinned: units +1 (F) -1 (E); edges +2 (C->A, F->A) -2 (D->C, E->D), 2 unchanged; cycles introduced 1 (A,B,C), resolved 0.
# POSITIVE CONTROLS (a check that cannot fail proves nothing):
#   PC-1 swapping the two sides swaps added/removed and turns the cycle into a RESOLVED one (the counts follow the sides);
#   PC-2 an after side WITHOUT C->A has no new cycle (the cycle count follows the source);
#   PC-3 the dot paints the added edge green, the removed one red dashed, an unchanged one grey, the cycle members thick red;
#   PC-4 --cap 2 cuts the drawing and counts the hidden units; without --counterpart-db the question is refused.
param(
  [Parameter(Mandatory)][string]$Exe,
  [switch]$ExpectRed,
  [string]$Scratch = ''
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $Scratch) { $Scratch = Join-Path $env:TEMP "g47-run-$PID" }
[IO.Directory]::CreateDirectory($Scratch) | Out-Null
$fail = 0; $pass = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
  if ($ok) { $script:pass++; Write-Host "PASS  $name" } else { $script:fail++; Write-Host "FAIL  $name  $detail" -ForegroundColor Red }
}
function Run-Engine([string[]]$a) {
  $ErrorActionPreference = 'Continue'
  $out = & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } } | Out-String
  [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out }
}
function Index-Fixture([string]$dir, [string]$db) {
  if (Test-Path $db) { [IO.File]::Delete($db) }
  $r = Run-Engine @('index', $dir, '--db', $db)
  if ($r.Code -ne 0) { throw "index failed: $($r.Text)" }
}
function Delta([string]$db, [string]$before, [string]$out, [string[]]$more = @()) {
  $a = @('ask', 'architecture-delta', '--target', 'project', '--db', $db, '--plain', '--out-root', $out)
  if ($before) { $a += @('--counterpart-db', $before) }
  Run-Engine ($a + $more)
}
function Emitter-Of([string]$out) {
  $m = Get-ChildItem $out -Recurse -Filter meta.json -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
  if (-not $m) { return $null }
  (Get-Content $m.FullName -Raw | ConvertFrom-Json | ForEach-Object { $_ }).emitter
}
function Json-Of($e) { if ($e) { $e | ConvertTo-Json -Compress } else { 'no meta' } }
function Dot-Text([string]$out) {
  $d = Get-ChildItem $out -Recurse -Filter *.dot -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
  if ($d) { Get-Content $d.FullName -Raw } else { '' }
}

$fx = Join-Path $repo 'tests\fixtures\g47'
$dbBefore = Join-Path $Scratch 'before.sqlite'
$dbAfter = Join-Path $Scratch 'after.sqlite'
Index-Fixture (Join-Path $fx 'before') $dbBefore
Index-Fixture (Join-Path $fx 'after') $dbAfter

if ($ExpectRed) {
  $r = Delta $dbAfter $dbBefore (Join-Path $Scratch 'red')
  Check 'RED architecture-delta refused as unknown question' (($r.Code -ne 0) -and ($r.Text -match 'unknown question')) "exit=$($r.Code) $($r.Text)"
  Write-Host "RED: $pass pass, $fail fail"; exit $(if ($fail) { 1 } else { 0 })
}

$o1 = Join-Path $Scratch 'd1'
$r = Delta $dbAfter $dbBefore $o1
Check 'architecture-delta exits 0' ($r.Code -eq 0) $r.Text
$e = Emitter-Of $o1
Check 'units: 1 added (F), 1 removed (E)' ($e -and $e.UnitsAdded -eq 1 -and $e.UnitsRemoved -eq 1) (Json-Of $e)
Check 'edges: 2 added, 2 removed, 2 unchanged' ($e -and $e.EdgesAdded -eq 2 -and $e.EdgesRemoved -eq 2 -and $e.EdgesUnchanged -eq 2) (Json-Of $e)
Check 'cycles: 1 introduced, 0 resolved' ($e -and $e.CyclesIntroduced -eq 1 -and $e.CyclesResolved -eq 0) (Json-Of $e)
$dot = Dot-Text $o1
Check 'PC-3 added edge green' ($dot -match '#2F9E44.{0,40}penwidth=3') $dot
Check 'PC-3 removed edge red dashed' ($dot -match 'color="#E03131", style=dashed') $dot
Check 'PC-3 an unchanged edge grey' ($dot -match 'color="#9AA3B2", style=solid') $dot
Check 'PC-3 cycle member outlined thick red' ($dot -match 'label="UnitA", color="#C92A2A".*penwidth=3') $dot
Check 'PC-3 unit F (added) green fill, unit E (removed) red fill' (($dot -match 'label="UnitF"[^;]*#E6F6E9') -and ($dot -match 'label="UnitE"[^;]*#FDE8E8')) $dot

# PC-1: the sides swapped
$o2 = Join-Path $Scratch 'd2'
$r = Delta $dbBefore $dbAfter $o2
$e = Emitter-Of $o2
Check 'PC-1 swapped: units +1/-1 swap, no new cycle, 1 resolved' ($e -and $e.UnitsAdded -eq 1 -and $e.UnitsRemoved -eq 1 -and $e.EdgesAdded -eq 2 -and $e.CyclesIntroduced -eq 0 -and $e.CyclesResolved -eq 1) (Json-Of $e)

# PC-2: an after side without the closing edge
$fxv = Join-Path $Scratch 'afterv'; [IO.Directory]::CreateDirectory($fxv) | Out-Null
foreach ($f in Get-ChildItem (Join-Path $fx 'after') -Filter *.pas) { Copy-Item $f.FullName $fxv }
$c = [IO.File]::ReadAllText((Join-Path $fx 'after\UnitC.pas')).Replace("uses`r`n  UnitA;", "uses`r`n  System.SysUtils;")
[IO.File]::WriteAllText((Join-Path $fxv 'UnitC.pas'), $c, [Text.Encoding]::ASCII)
$dbv = Join-Path $Scratch 'afterv.sqlite'
Index-Fixture $fxv $dbv
$o3 = Join-Path $Scratch 'd3'
$r = Delta $dbv $dbBefore $o3
$e = Emitter-Of $o3
Check 'PC-2 no closing edge: 0 cycles introduced, 1 edge added (F->A)' ($e -and $e.CyclesIntroduced -eq 0 -and $e.EdgesAdded -eq 1) (Json-Of $e)

# PC-4
$o4 = Join-Path $Scratch 'd4'
$r = Delta $dbAfter $dbBefore $o4 @('--cap', '2')
$e = Emitter-Of $o4
Check 'PC-4 --cap 2: 2 units drawn, the rest hidden, the label says so' ($e -and $e.Shown -eq 2 -and $e.Hidden -ge 1 -and ((Dot-Text $o4) -match 'not shown \(cap 2\)')) (Json-Of $e)
$r = Delta $dbAfter '' (Join-Path $Scratch 'd5')
Check 'PC-4 no counterpart db: refused, says what is missing' (($r.Code -ne 0) -and ($r.Text -match 'counterpart-db')) "exit=$($r.Code) $($r.Text)"

Write-Host "G47: $pass pass, $fail fail"
exit $(if ($fail) { 1 } else { 0 })