<#
  run_exports_clause_refs.ps1 -- wave 150 lane X1 (T2 FOUND): an `exports` clause emits a ref per entry.

  Fixture tests\fixtures\x1-exports-150 (folder index into a temp DB, then `sql --json`; rows are POSITIONAL):
    E1  X1Lib.dpr `exports X1LibAdd name 'x1_lib_add', X1Twice index 2;` -> one 'call' ref per entry
        (X1LibAdd at line 16, X1Twice at line 17).
    E2  the X1Twice export ref is bound to uX1LibUnit.X1Twice (call_edges), so find-callers lists it.
    E3  lint-all unused-public-symbol no longer flags X1Twice.
  RED on the 1.49.0-alpha base build: no ref at lines 16-17; unused-public-symbol flags X1Twice.
  POSITIVE CONTROL: X1Unused (declared, never exported, never called) is STILL flagged by
  unused-public-symbol, and has no ref at all.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-x1-exports-$PID"
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
$Fx  = (Resolve-Path (Join-Path $PSScriptRoot '..\fixtures\x1-exports-150')).Path
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$Db = Join-Path $WorkDir 'exports.sqlite'
if (Test-Path $Db) { [IO.File]::Delete($Db) }

$null = & $Exe index $Fx --db $Db 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: index exit $LASTEXITCODE" -ForegroundColor Red; exit 2 }

function Rows([string]$q) {
  $raw = & $Exe sql --db $Db --query $q --json --limit 500 2>$null
  if ($LASTEXITCODE -ne 0) { return ,@() }
  $j = ($raw | Where-Object { $_ -notmatch '^\(loaded' }) -join "`n" | ConvertFrom-Json
  return ,@($j.rows)
}

Write-Host "== X1 exports clause refs ($Exe)"

# rows: [0]=kind [1]=name_text [2]=start_line [3]=bound target qname or null
$r = Rows ("SELECT r.kind, r.name_text, r.start_line, (SELECT s.qualified_name FROM call_edges ce JOIN symbols s ON s.id=ce.target_symbol_id WHERE ce.ref_id=r.id) " +
           "FROM refs r JOIN files f ON f.id=r.file_id WHERE f.path LIKE '%\X1Lib.dpr' AND r.start_line IN (16,17) ORDER BY r.start_line")
Check 'E1 two refs on the exports lines' ($r.Count -eq 2) "got $($r.Count) row(s)"
$add = @($r | Where-Object { $_[1] -eq 'X1LibAdd' -and $_[2] -eq 16 -and $_[0] -eq 'call' })
$twc = @($r | Where-Object { $_[1] -eq 'X1Twice'  -and $_[2] -eq 17 -and $_[0] -eq 'call' })
Check 'E1 X1LibAdd export -> call ref at line 16' ($add.Count -eq 1)
Check 'E1 X1Twice export -> call ref at line 17' ($twc.Count -eq 1)
Check 'E2 X1Twice export bound to uX1LibUnit.X1Twice' ($twc.Count -eq 1 -and $twc[0][3] -eq 'uX1LibUnit.X1Twice') "target=$(if ($twc.Count) { $twc[0][3] })"

$u = Rows "SELECT COUNT(*) FROM refs WHERE name_text='X1Unused'"
Check 'CONTROL X1Unused has no ref' ($u.Count -eq 1 -and $u[0][0] -eq 0)

Push-Location $WorkDir
try { $raw = & $Exe lint-all --db $Db --json 2>$null | Out-String } finally { Pop-Location }
$f = @($raw | ConvertFrom-Json) | Where-Object { $_.rule -eq 'unused-public-symbol' }
$fTwice  = @($f | Where-Object { $_.message -match '\bX1Twice\b' })
$fUnused = @($f | Where-Object { $_.message -match '\bX1Unused\b' })
Check 'E3 unused-public-symbol does not flag X1Twice' ($fTwice.Count -eq 0)
Check 'CONTROL unused-public-symbol still flags X1Unused' ($fUnused.Count -eq 1) "got $($fUnused.Count)"

Write-Host ("== {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 } else { exit 0 }