<#
  run_raise_handle_refs.ps1 -- raise / handler sites emit their own refs.kind rows.

  Spec: docs\superpowers\specs\2026-10-26-extract-raise-handle-facts.md (sec. 2, 7).
  Before 1.36.0 `raise EFoo.Create(..)` emitted only `read EFoo` and `on E: EFoo do`
  only `type_use EFoo`, so exception-paths re-read SOURCE to tell them apart. The
  extractor now adds five kinds (ADDED rows; existing rows at the same site stay):
    raise       raise <T>.Create*(..)  (also paren-less `raise T.Create;`)
    raise-expr  any other raise <expr> (root identifier)
    reraise     bare `raise;`
    handle      on [E:] T do           (the type, rhs of a qualified name)
    handle-all  an `except` with no handler, and the `else` after handlers

  Checks:
    A. the rows on tests\fixtures\raise-handle equal RaiseHandle.expected.tsv EXACTLY
       (kind, name_text, start_line, start_col, receiver_text, enclosing qualified name);
    B. positive control: the same compare against the expected set minus one line
       FAILS, and a non-zero row count per kind (a wrong field name = silent zero rows);
    C. negatives: no new-kind row in the try..finally-only routine, none named after
       the handler VARIABLE at its own column, none for `Exception.Create` not raised;
    D. (only with -BaselineExe) the existing kinds are byte-identical between the
       baseline engine and -Exe on the fixture (spec 7.3).

  `sql --json` rows are POSITIONAL arrays: mapped onto columns[].name below.
#>
[CmdletBinding()]
param(
  [string]$Exe         = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$BaselineExe = '',
  [string]$WorkDir     = "$env:TEMP\drag-lint-raise-handle-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$FixtureDir = (Resolve-Path "$PSScriptRoot\..\fixtures\raise-handle").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory $work | Out-Null
Copy-Item (Join-Path $FixtureDir 'RaiseHandle.pas'), (Join-Path $FixtureDir 'RaiseHandleProj.dpr') $work

$NewKinds = "'raise','raise-expr','reraise','handle','handle-all'"

function Invoke-Sql([string]$EngineExe, [string]$Db, [string]$Query) {
  $raw = (& $EngineExe sql --query $Query --db $Db --json 2>$null) -join "`n"
  $env = $raw | ConvertFrom-Json
  $names = @($env.columns | ForEach-Object { $_.name })
  $out = foreach ($r in $env.rows) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $names.Count; $i++) { $o[$names[$i]] = $r[$i] }
    [pscustomobject]$o
  }
  return ,@($out)
}

function Index-Fixture([string]$EngineExe, [string]$Db) {
  $o = & $EngineExe index $work --db $Db 2>&1
  return @{ Exit = $LASTEXITCODE; Out = ($o -join ' | ') }
}

$db = Join-Path $WorkDir 'raise.sqlite'
$ix = Index-Fixture $Exe $db
Check 'index exits 0' ($ix.Exit -eq 0) "exit=$($ix.Exit)"

$q = "SELECT r.kind, r.name_text, r.start_line, r.start_col, COALESCE(r.receiver_text,'') AS receiver_text, " +
     "COALESCE(s.qualified_name,'') AS enclosing FROM refs r LEFT JOIN symbols s ON s.id = r.enclosing_symbol_id " +
     "WHERE r.kind IN ($NewKinds) ORDER BY r.start_line, r.start_col, r.kind"
$rows = Invoke-Sql $Exe $db $q
$actual = @($rows | ForEach-Object { '{0}|{1}|{2}|{3}|{4}|{5}' -f $_.kind, $_.name_text, $_.start_line, $_.start_col, $_.receiver_text, $_.enclosing })

$expected = @(Get-Content (Join-Path $FixtureDir 'RaiseHandle.expected.tsv') | Select-Object -Skip 1 |
  Where-Object { $_ -ne '' } | ForEach-Object { $_ -replace "`t", '|' })

function Compare-Exact([string[]]$Exp, [string[]]$Act) {
  $e = @($Exp | Sort-Object); $a = @($Act | Sort-Object)
  if ($e.Count -ne $a.Count) { return $false }
  for ($i = 0; $i -lt $e.Count; $i++) { if ($e[$i] -cne $a[$i]) { return $false } }
  return $true
}

# A. exact compare
$same = Compare-Exact $expected $actual
$diff = ''
if (-not $same) {
  $miss  = @($expected | Where-Object { $actual -notcontains $_ })
  $extra = @($actual   | Where-Object { $expected -notcontains $_ })
  $diff = "missing=[" + ($miss -join '; ') + "] extra=[" + ($extra -join '; ') + "]"
}
Check "A. rows equal RaiseHandle.expected.tsv ($($expected.Count) expected, $($actual.Count) actual)" $same $diff

# B. positive controls
$short = @($expected | Select-Object -Skip 1)
Check 'B. control: the compare FAILS against the expected set minus one line' (-not (Compare-Exact $short $actual))
foreach ($k in 'raise', 'raise-expr', 'reraise', 'handle', 'handle-all') {
  $n = @($rows | Where-Object { $_.kind -eq $k }).Count
  Check "B. kind '$k' has a non-zero row count" ($n -gt 0) "rows=$n"
}

# C. negatives
$neg = @($rows | Where-Object { $_.enclosing -eq 'RaiseHandle.Negatives' })
Check 'C. no raise/handle row in the try..finally-only routine (incl. Exception.Create not raised)' ($neg.Count -eq 0) ("rows=" + ($neg | ConvertTo-Json -Compress))
$hv = @($rows | Where-Object { $_.name_text -eq 'E' -and $_.kind -like 'handle*' })
Check 'C. the handler variable E is never a handle row' ($hv.Count -eq 0) ("rows=" + ($hv | ConvertTo-Json -Compress))
$fin = @($rows | Where-Object { $_.name_text -eq 'finally' })
Check 'C. try..finally emits no handle-all' ($fin.Count -eq 0)

# D. zero-diff on the existing kinds (optional)
if ($BaselineExe -ne '') {
  $BaselineExe = (Resolve-Path $BaselineExe).Path
  $db0 = Join-Path $WorkDir 'baseline.sqlite'
  $ix0 = Index-Fixture $BaselineExe $db0
  Check 'D. baseline index exits 0' ($ix0.Exit -eq 0) "exit=$($ix0.Exit)"
  $q2 = "SELECT kind, name_text, start_line, start_col, end_line, end_col, COALESCE(receiver_text,'') AS rt FROM refs " +
        "WHERE kind NOT IN ($NewKinds) ORDER BY start_line, start_col, kind, name_text"
  $r0 = Invoke-Sql $BaselineExe $db0 $q2
  $r1 = Invoke-Sql $Exe $db $q2
  $before = @($r0 | ForEach-Object { ($_.PSObject.Properties.Value) -join '|' })
  $after  = @($r1 | ForEach-Object { ($_.PSObject.Properties.Value) -join '|' })
  Check "D. existing kinds identical to the baseline engine ($($before.Count) rows)" (($before.Count -gt 0) -and (Compare-Exact $before $after)) "before=$($before.Count) after=$($after.Count)"
}

if ($script:Failed) { Write-Host 'run_raise_handle_refs: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_raise_handle_refs: PASS' -ForegroundColor Green
exit 0
} catch {
  Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
  exit 2
}
