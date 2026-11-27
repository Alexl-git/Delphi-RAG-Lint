# Acceptance runner for lane G51 (1.56): `import-coverage` and `ask risk` (gap G-51).
#
# Usage: run_v156_G51.ps1 -Exe <drag-lint.exe> [-ExpectRed] [-Scratch <dir>]
#   -ExpectRed : the engine is the BASE engine; the verb and the question must be refused (non-zero exit).
#                Exit 0 = the RED is real. Without it the runner asserts the GREEN behaviour.
#
# Fixture tests\fixtures\g51: Calc.pas (Simple cc1, Untracked cc2, TCalc.Branchy cc6, TCalc.Middling cc4) and
# coverage.xml (DelphiCodeCoverage EMMA shape): Simple 1/1, Branchy 0/8, Middling 2/10, Removed 1/2 (no such
# routine), Ghost.pas TGhost.Boo 2/4 (no such file); Untracked has no record.
#   import   : 5 records, 3 matched, 2 unmatched records, 1 unmatched file (Ghost.pas), 1 indexed routine
#              without a record; the sidecar <db>.coverage.json holds all 5 records (nothing dropped).
#   risk     : score = cc^2 * (1-cov)^3 + cc, HAND-COMPUTED: Branchy 42.000, Middling 12.192, Untracked 6.000
#              (no record = 0 coverage), Simple 1.000; ranked in that order.
#   POSITIVE CONTROLS (a check that cannot fail proves nothing):
#     PC-1 Branchy coverage raised to 8/8 (re-import): it leaves rank 1, its score becomes its cc (6.000),
#          Middling becomes rank 1;
#     PC-2 the score comparer REJECTS the hand table with one score changed by 1;
#     PC-3 an index with NO sidecar: CoverageImported = false, no routine has data, Middling scores 20.000
#          (cc 4 at zero coverage), i.e. not the 12.192 of the imported case;
#     PC-4 a file that is no coverage report is refused (exit 2) and writes no sidecar.
param(
  [Parameter(Mandatory)][string]$Exe,
  [switch]$ExpectRed,
  [string]$Scratch = ''
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $Scratch) { $Scratch = Join-Path $env:TEMP "g51-run-$PID" }
[IO.Directory]::CreateDirectory($Scratch) | Out-Null
$fail = 0; $pass = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
  if ($ok) { $script:pass++; Write-Host "PASS  $name" } else { $script:fail++; Write-Host "FAIL  $name  $detail" -ForegroundColor Red }
}
function Run-Engine([string[]]$a) {
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $out = & $Exe @a 2>&1 | Out-String
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  [pscustomobject]@{ Code = $code; Text = $out }
}
function Index-Fixture([string]$dir, [string]$db) {
  foreach ($f in @($db, "$db.coverage.json")) { if (Test-Path $f) { [IO.File]::Delete($f) } }
  $r = Run-Engine @('index', $dir, '--db', $db)
  if ($r.Code -ne 0) { throw "index failed: $($r.Text)" }
}
function Ask([string]$db, [string]$out) {
  Run-Engine @('ask', 'risk', '--target', 'project', '--db', $db, '--plain', '--out-root', $out)
}
function Newest([string]$out, [string]$filter) {
  Get-ChildItem $out -Recurse -Filter $filter -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
}
function Meta-Of([string]$out) {
  $m = Newest $out 'meta.json'
  if (-not $m) { return $null }
  Get-Content $m.FullName -Raw | ConvertFrom-Json
}
function Read-Risk([string]$out) {
  $csv = Newest $out 'risk.csv'
  $rows = @()
  if ($csv) { $rows = @(Import-Csv $csv.FullName) }
  , $rows
}
function Short([string]$name) { ($name -split '\.')[-1] }
function Scores-Match($rows, $want) {
  # $want: ordered list of @(name, score); the rows must list exactly those names in that order, scores to 0.001
  if ($rows.Count -ne $want.Count) { return $false }
  for ($i = 0; $i -lt $want.Count; $i++) {
    if ((Short $rows[$i].routine) -ne $want[$i][0]) { return $false }
    if ([math]::Abs([double]$rows[$i].score - $want[$i][1]) -gt 0.001) { return $false }
  }
  $true
}

$fx = Join-Path $repo 'tests\fixtures\g51'
$xml = Join-Path $fx 'coverage.xml'
$db = Join-Path $Scratch 'g51.sqlite'
Index-Fixture $fx $db

if ($ExpectRed) {
  $r = Run-Engine @('import-coverage', '--file', $xml, '--db', $db)
  Check 'RED import-coverage is not a verb of the base engine' ($r.Code -ne 0) "exit=$($r.Code) $($r.Text)"
  $r = Ask $db (Join-Path $Scratch 'red')
  Check 'RED ask risk refused as unknown question' (($r.Code -ne 0) -and ($r.Text -match 'unknown question')) "exit=$($r.Code) $($r.Text)"
  Write-Host "RED: $pass pass, $fail fail"; exit $(if ($fail) { 1 } else { 0 })
}

# ---- import ----
$r = Run-Engine @('import-coverage', '--file', $xml, '--db', $db, '--json')
Check 'import exits 0' ($r.Code -eq 0) $r.Text
$j = $null
try { $j = ($r.Text -replace '(?s)^.*?(\{)', '$1') | ConvertFrom-Json } catch { }
Check 'import counts: 5 records, 3 matched, 2 unmatched records, 1 indexed routine without a record' ($j -and $j.records -eq 5 -and $j.matched -eq 3 -and $j.unmatched_records -eq 2 -and $j.indexed_routines_without_record -eq 1) $r.Text
Check 'unmatched file is named: Ghost.pas' ($j -and (@($j.unmatched_files) -contains 'Ghost.pas')) $r.Text
Check 'unmatched records are named (TCalc.Removed, TGhost.Boo)' ($j -and ((@($j.unmatched_routines) -join ';') -match 'TCalc\.Removed') -and ((@($j.unmatched_routines) -join ';') -match 'TGhost\.Boo')) $r.Text
$side = "$db.coverage.json"
$sj = if (Test-Path $side) { Get-Content $side -Raw | ConvertFrom-Json } else { $null }
Check 'sidecar keeps all 5 records (nothing dropped)' ($sj -and $sj.schema -eq 'coverage/1' -and @($sj.routines).Count -eq 5)
$t = Run-Engine @('import-coverage', '--file', $xml, '--db', $db)
Check 'text output lists the unmatched file and record' (($t.Text -match 'file Ghost\.pas') -and ($t.Text -match 'record Calc\.pas: TCalc\.Removed')) $t.Text

# ---- risk ----
$want = @(@('Branchy', 42.0), @('Middling', 12.192), @('Untracked', 6.0), @('Simple', 1.0))
$o1 = Join-Path $Scratch 'r1'
$a = Ask $db $o1
Check 'ask risk exits 0' ($a.Code -eq 0) $a.Text
$rows = Read-Risk $o1
Check 'risk ranking and scores equal the hand-computed table' (Scores-Match $rows $want) (($rows | ForEach-Object { "$($_.routine)=$($_.score)" }) -join ' ')
$m = Meta-Of $o1
$e = if ($m) { $m.emitter } else { $null }
Check 'meta: Scored=4, WithCoverage=3, WithoutCoverage=1, CoverageImported' ($e -and $e.Scored -eq 4 -and $e.WithCoverage -eq 3 -and $e.WithoutCoverage -eq 1 -and $e.CoverageImported -eq $true) ($e | ConvertTo-Json -Compress)
$bad = @(@('Branchy', 43.0), @('Middling', 12.192), @('Untracked', 6.0), @('Simple', 1.0))
Check 'PC-2 the score comparer rejects the table with one score changed by 1' (-not (Scores-Match $rows $bad))

# PC-1: cover the riskiest routine fully
$x2 = Join-Path $Scratch 'cov-branchy-full.xml'
[IO.File]::WriteAllText($x2, ([IO.File]::ReadAllText($xml).Replace('0% (0/8)', '100% (8/8)')))
$r2 = Run-Engine @('import-coverage', '--file', $x2, '--db', $db)
$o2 = Join-Path $Scratch 'r2'
$null = Ask $db $o2
$rows2 = Read-Risk $o2
$b = $rows2 | Where-Object { (Short $_.routine) -eq 'Branchy' }
Check 'PC-1 Branchy at 100% leaves rank 1, scores its cc (6.000); Middling is rank 1' ($r2.Code -eq 0 -and $b -and [int]$b.rank -gt 1 -and [math]::Abs([double]$b.score - 6.0) -lt 0.001 -and (Short $rows2[0].routine) -eq 'Middling') (($rows2 | ForEach-Object { "$($_.rank):$($_.routine)=$($_.score)" }) -join ' ')

# PC-3: no sidecar
$db3 = Join-Path $Scratch 'g51-nocov.sqlite'
Index-Fixture $fx $db3
$o3 = Join-Path $Scratch 'r3'
$null = Ask $db3 $o3
$rows3 = Read-Risk $o3
$mid = $rows3 | Where-Object { (Short $_.routine) -eq 'Middling' }
$e3 = (Meta-Of $o3).emitter
Check 'PC-3 no import: CoverageImported=false, WithCoverage=0, Middling scores 20.000' ($e3 -and $e3.CoverageImported -eq $false -and $e3.WithCoverage -eq 0 -and $mid -and [math]::Abs([double]$mid.score - 20.0) -lt 0.001) ($e3 | ConvertTo-Json -Compress)

# PC-4: not a report
$notRep = Join-Path $Scratch 'not-a-report.xml'
[IO.File]::WriteAllText($notRep, '<?xml version="1.0"?><project><name>x</name></project>')
$r4 = Run-Engine @('import-coverage', '--file', $notRep, '--db', $db3)
Check 'PC-4 a file that is no coverage report is refused (exit 2) and writes no sidecar' ($r4.Code -eq 2 -and -not (Test-Path "$db3.coverage.json")) "exit=$($r4.Code) $($r4.Text)"

Write-Host "GREEN: $pass pass, $fail fail"
exit $(if ($fail) { 1 } else { 0 })
