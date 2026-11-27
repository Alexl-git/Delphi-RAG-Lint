# Acceptance runner for lane CHB-1 (1.56): `ask class-diagram` (G-43) and `ask sequence` (G-45).
#
# Usage: run_v156_CHB1.ps1 -Exe <drag-lint.exe> [-ExpectRed] [-Scratch <dir>]
#   -ExpectRed : the engine is the BASE engine; both questions must be refused as "unknown question"
#                (exit 2). Exit 0 = the RED is real. Without it the runner asserts the GREEN behaviour.
#
# GREEN assertions (fixture tests\fixtures\chb1\ChbModel.pas, indexed into a DB under -Scratch):
#   class-diagram TOwner : Classes=3, AncestorEdges=1, FieldEdges=2, DescendantEdges=0 (3 classes, 1 ancestor
#                          edge, 2 field-type edges, exactly).
#   sequence TOwner.Run  : the message order in graph.dot equals the refs order of the routine
#                          (SELECT name_text FROM refs WHERE enclosing_symbol_id = <Run> AND kind='call' ORDER BY id).
#   POSITIVE CONTROLS (a check that cannot fail proves nothing):
#     PC-1 a variant fixture with a third class-typed field must give FieldEdges=3 (the count follows the data);
#     PC-2 the order comparer must REJECT the reversed refs order;
#     PC-3 an unknown target is refused (exit non-zero), not answered with an empty diagram.
param(
  [Parameter(Mandatory)][string]$Exe,
  [switch]$ExpectRed,
  [string]$Scratch = ''
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $Scratch) { $Scratch = Join-Path $env:TEMP "chb1-run-$PID" }
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
function Ask([string]$q, [string]$target, [string]$db, [string]$out) {
  Run-Engine @('ask', $q, '--target', $target, '--db', $db, '--plain', '--out-root', $out)
}
function Meta-Of([string]$out) {
  $m = Get-ChildItem $out -Recurse -Filter meta.json | Sort-Object LastWriteTime | Select-Object -Last 1
  if (-not $m) { return $null }
  Get-Content $m.FullName -Raw | ConvertFrom-Json
}
function Dot-Of([string]$out) {
  Get-ChildItem $out -Recurse -Filter *.dot | Sort-Object LastWriteTime | Select-Object -Last 1
}

$fx = Join-Path $repo 'tests\fixtures\chb1'
$db = Join-Path $Scratch 'chb1.sqlite'
Index-Fixture $fx $db

if ($ExpectRed) {
  foreach ($q in @(@('class-diagram', 'TOwner'), @('sequence', 'ChbModel.TOwner.Run'))) {
    $r = Ask $q[0] $q[1] $db (Join-Path $Scratch 'red')
    Check "RED $($q[0]) refused as unknown question" (($r.Code -ne 0) -and ($r.Text -match 'unknown question')) "exit=$($r.Code) $($r.Text)"
  }
  Write-Host "RED: $pass pass, $fail fail"; exit $(if ($fail) { 1 } else { 0 })
}

# ---- class-diagram ----
$o1 = Join-Path $Scratch 'cd1'
$r = Ask 'class-diagram' 'TOwner' $db $o1
Check 'class-diagram exits 0' ($r.Code -eq 0) $r.Text
$m = Meta-Of $o1
$e = if ($m) { $m.emitter } else { $null }
Check 'class-diagram: 3 classes' ($e -and $e.Classes -eq 3) ($e | ConvertTo-Json -Compress)
Check 'class-diagram: 1 ancestor edge' ($e -and $e.AncestorEdges -eq 1) ($e | ConvertTo-Json -Compress)
Check 'class-diagram: 2 field-type edges' ($e -and $e.FieldEdges -eq 2) ($e | ConvertTo-Json -Compress)
Check 'class-diagram: 0 descendant edges' ($e -and $e.DescendantEdges -eq 0) ($e | ConvertTo-Json -Compress)

# PC-1: a third class-typed field must raise the field-edge count to 3
$fx2 = Join-Path $Scratch 'fx2'; [IO.Directory]::CreateDirectory($fx2) | Out-Null
$src = [IO.File]::ReadAllText((Join-Path $fx 'ChbModel.pas'))
$src = $src.Replace("    FCount: Integer;", "    FCount: Integer;`r`n    FPart2: TPart2;").Replace("  TBase = class", "  TPart2 = class`r`n  end;`r`n`r`n  TBase = class")
[IO.File]::WriteAllText((Join-Path $fx2 'ChbModel.pas'), $src, [Text.Encoding]::ASCII)
$db2 = Join-Path $Scratch 'chb1b.sqlite'
Index-Fixture $fx2 $db2
$o2 = Join-Path $Scratch 'cd2'
$r = Ask 'class-diagram' 'TOwner' $db2 $o2
$m = Meta-Of $o2
Check 'PC-1 variant with a third field-type class: FieldEdges=3, Classes=4' ($m -and $m.emitter.FieldEdges -eq 3 -and $m.emitter.Classes -eq 4) ($m.emitter | ConvertTo-Json -Compress)

# descendants: TBase has the descendant TOwner and (via field FBase) is a plain focus
$o3 = Join-Path $Scratch 'cd3'
$r = Ask 'class-diagram' 'TBase' $db $o3
$m = Meta-Of $o3
Check 'class-diagram TBase: 1 descendant edge, 0 field edges' ($m -and $m.emitter.DescendantEdges -eq 1 -and $m.emitter.FieldEdges -eq 0) ($m.emitter | ConvertTo-Json -Compress)

# PC-3: unknown target refused
$r = Ask 'class-diagram' 'TNoSuchClass' $db (Join-Path $Scratch 'cd4')
Check 'PC-3 unknown class is refused' ($r.Code -ne 0) $r.Text

# ---- sequence ----
$o5 = Join-Path $Scratch 'sq1'
$r = Ask 'sequence' 'ChbModel.TOwner.Run' $db $o5
Check 'sequence exits 0' ($r.Code -eq 0) $r.Text
$q = & $Exe sql --db $db --json --query "SELECT r.name_text FROM refs r JOIN symbols s ON s.id = r.enclosing_symbol_id WHERE s.name = 'Run' AND r.kind = 'call' ORDER BY r.id" 2>&1 | Out-String
$j = ($q -replace '(?s)^.*?(\{)', '$1') | ConvertFrom-Json
$expected = @($j.rows | ForEach-Object { $_[0] })
$dot = Dot-Of $o5
$labels = @()
if ($dot) { $labels = @([regex]::Matches((Get-Content $dot.FullName -Raw), 'label="(\d+): ([^"]+)"') | ForEach-Object { $_.Groups[2].Value }) }
function Same-Order($a, $b) { ($a.Count -eq $b.Count) -and (($a -join '|') -ceq ($b -join '|')) }
Check "sequence: call order equals the refs order ($($expected -join ','))" ((Same-Order $labels $expected) -and $expected.Count -ge 3) "dot labels: $($labels -join ',')"
$rev = @($expected.Clone()); [Array]::Reverse($rev)
Check 'PC-2 the order comparer rejects the reversed refs order' (-not (Same-Order $labels $rev))
$m = Meta-Of $o5
Check 'sequence: Calls matches refs count' ($m -and $m.emitter.Calls -eq $expected.Count) ($m.emitter | ConvertTo-Json -Compress)

$r = Ask 'sequence' 'ChbModel.TOwner.NoSuchRoutine' $db (Join-Path $Scratch 'sq2')
Check 'sequence: unknown routine refused' ($r.Code -ne 0) $r.Text

Write-Host "CHB-1: $pass pass, $fail fail"
exit $(if ($fail) { 1 } else { 0 })
