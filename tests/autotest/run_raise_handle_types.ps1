<#
  run_raise_handle_types.ps1 -- raise / handle rows carry the exception TYPE.

  Spec: docs\superpowers\specs\2026-11-06-raise-handle-type-facts.md (sec. 3.1, 3.2, 5).
    reraise, and a raise-expr naming the handler variable: receiver_text = the type of the
    nearest enclosing `on .. do`; '' under a bare except, an else, or outside a handler.
    raise, handle: symbol_id bound to the type, when the DB holds it and one candidate wins.

  Checks:
    A. rows on tests\fixtures\raise-handle-types equal TypeFacts.expected.tsv EXACTLY
       (kind, name, line, col, receiver_text, enclosing, bound symbol's qualified name);
    B. controls: the compare FAILS on the set minus one line; a non-empty count of stamped and
       of bound rows; two types named EDup bind to two different symbols;
    C. resolve-only: the bound set survives `index --resolve-only` (the stream clears, then writes);
    D. (only with -BaselineExe) every other kind is identical, and usages + rename dry run answer
       the same on a type whose rows now carry symbol_id beside a read / type_use.

  `sql --json` rows are POSITIONAL arrays: mapped onto columns[].name below.
#>
[CmdletBinding()]
param(
  [string]$Exe         = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$BaselineExe = '',
  [string]$WorkDir     = "$env:TEMP\drag-lint-raise-types-$PID"
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
$FixtureDir = (Resolve-Path "$PSScriptRoot\..\fixtures\raise-handle-types").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory $work | Out-Null
Copy-Item (Join-Path $FixtureDir '*.pas'), (Join-Path $FixtureDir '*.dpr') $work

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
function Compare-Exact([string[]]$Exp, [string[]]$Act) {
  $e = @($Exp | Sort-Object); $a = @($Act | Sort-Object)
  if ($e.Count -ne $a.Count) { return $false }
  for ($i = 0; $i -lt $e.Count; $i++) { if ($e[$i] -cne $a[$i]) { return $false } }
  return $true
}
function Get-Facts([string]$EngineExe, [string]$Db) {
  $q = "SELECT r.kind, r.name_text, r.start_line, r.start_col, COALESCE(r.receiver_text,'') AS rt, " +
       "COALESCE(s.qualified_name,'') AS enclosing, COALESCE(b.qualified_name,'') AS bound FROM refs r " +
       "LEFT JOIN symbols s ON s.id = r.enclosing_symbol_id LEFT JOIN symbols b ON b.id = r.symbol_id " +
       "WHERE r.kind IN ($NewKinds)"
  $rows = Invoke-Sql $EngineExe $Db $q
  return ,@($rows | ForEach-Object { '{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f $_.kind, $_.name_text, $_.start_line, $_.start_col, $_.rt, $_.enclosing, $_.bound })
}

$db = Join-Path $WorkDir 'types.sqlite'
$null = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
$actual = Get-Facts $Exe $db
$expected = @(Get-Content (Join-Path $FixtureDir 'TypeFacts.expected.tsv') | Select-Object -Skip 1 |
  Where-Object { $_ -ne '' } | ForEach-Object {
    # an unbound row ends at `enclosing`: the tsv keeps no trailing tab, the actual line keeps its empty field
    $l = $_.TrimEnd() -replace "`t", '|'; if (($l -split '\|').Count -eq 6) { $l + '|' } else { $l } })

$same = Compare-Exact $expected $actual
$diff = ''
if (-not $same) {
  $miss  = @($expected | Where-Object { $actual -notcontains $_ })
  $extra = @($actual   | Where-Object { $expected -notcontains $_ })
  $diff = "missing=[" + ($miss -join '; ') + "] extra=[" + ($extra -join '; ') + "]"
}
Check "A. rows equal TypeFacts.expected.tsv ($($expected.Count) expected, $($actual.Count) actual)" $same $diff

Check 'B. control: the compare FAILS against the expected set minus one line' (-not (Compare-Exact @($expected | Select-Object -Skip 1) $actual))
$stamped = @($actual | Where-Object { ($_ -split '\|')[4] -ne '' -and ($_ -split '\|')[0] -in 'reraise','raise-expr' })
Check 'B. stamped reraise / raise-expr rows = 3' ($stamped.Count -eq 3) "rows=$($stamped.Count)"
$bound = @($actual | Where-Object { ($_ -split '\|')[6] -ne '' })
Check 'B. bound rows = 5' ($bound.Count -eq 5) "rows=$($bound.Count)"
$dup = @($actual | Where-Object { ($_ -split '\|')[1] -eq 'EDup' } | ForEach-Object { ($_ -split '\|')[6] } | Sort-Object -Unique)
Check 'B. two EDup bind to two symbols (ExcA.EDup, ExcB.EDup)' (($dup -join ',') -ceq 'ExcA.EDup,ExcB.EDup') ($dup -join ',')

$null = & $Exe index $work --db $db --resolve-only 2>&1
Check 'C. index --resolve-only exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
$again = Get-Facts $Exe $db
Check 'C. the facts are identical after a resolve-only pass' (Compare-Exact $expected $again)

if ($BaselineExe -ne '') {
  $BaselineExe = (Resolve-Path $BaselineExe).Path
  $db0 = Join-Path $WorkDir 'baseline.sqlite'
  $null = & $BaselineExe index $work --db $db0 2>&1
  Check 'D. baseline index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  $q2 = "SELECT r.kind, r.name_text, r.start_line, r.start_col, r.end_line, r.end_col, COALESCE(r.receiver_text,'') AS rt, " +
        "COALESCE(b.qualified_name,'') AS bound FROM refs r LEFT JOIN symbols b ON b.id = r.symbol_id WHERE r.kind NOT IN ($NewKinds)"
  $rows0 = Invoke-Sql $BaselineExe $db0 $q2
  $rows1 = Invoke-Sql $Exe $db $q2
  $before = @($rows0 | ForEach-Object { ($_.PSObject.Properties.Value) -join '|' })
  $after  = @($rows1 | ForEach-Object { ($_.PSObject.Properties.Value) -join '|' })
  Check "D. other kinds identical to the baseline ($($before.Count) rows)" (($before.Count -gt 0) -and (Compare-Exact $before $after)) "before=$($before.Count) after=$($after.Count)"
  $u0 = (& $BaselineExe usages --name ELocal --db $db0 --json 2>$null) -join "`n"
  $u1 = (& $Exe usages --name ELocal --db $db --json 2>$null) -join "`n"
  Check 'D. control: the baseline answers raises/handles name-only; this engine exact' (($u0 -match 'name-only') -and ($u1 -notmatch 'name-only')) "u0=$($u0.Length) u1=$($u1.Length)"
  Check 'D. usages --name ELocal --json differs ONLY in that' (($u0 -replace 'name-only', 'exact') -ceq $u1) "u0=$($u0.Length) u1=$($u1.Length)"
  # a raise / handle row beside a read / type_use, both bound: one edit per position, not two.
  $r0 = @(& $BaselineExe rename --qname TypeFacts.ELocal --to ELocal2 --dry-run --db $db0 2>$null | Where-Object { $_ -match '^\s+L\d+:C\d+' })
  $r1 = @(& $Exe rename --qname TypeFacts.ELocal --to ELocal2 --dry-run --db $db 2>$null | Where-Object { $_ -match '^\s+L\d+:C\d+' })
  Check 'D. rename dry run: the same 4 edits' (($r0.Count -eq 4) -and (Compare-Exact $r0 $r1)) "r0=$($r0.Count) r1=$($r1.Count): $($r1 -join ';')"
}

if ($script:Failed) { Write-Host 'run_raise_handle_types: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_raise_handle_types: PASS' -ForegroundColor Green
exit 0
} catch {
  Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
  exit 2
}
