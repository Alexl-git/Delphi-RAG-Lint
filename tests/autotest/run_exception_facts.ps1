<#
  run_exception_facts.ps1 -- `exception-facts`: which routine raises and handles which type.

  Spec: docs\superpowers\specs\2026-11-06-raise-handle-type-facts.md, sec. 3.3 + 5.H.
  Fixture: tests\fixtures\raise-handle-types.

  Checks:
    A. --target TypeFacts.Stamp --json: the rows, exact (action, type, qname, via, line, col);
    B. --name: both directions; a bare name lists two types of that name, a qualified one picks one;
       a reraise and a handler-var raise are listed under their stamped type; no ancestry;
    C. text output and the count line;
    D. usage errors exit 2: neither selector, both selectors, no DB;
    E. controls: the compare FAILS on a set minus one row; a routine with no sites is exit 0 and count 0;
    F. (only with -BaselineExe) a DB written by the baseline engine: the verb answers, the reraise under
       `on EAbort do` reads via=unknown, and no row reads via=bound. The fact is what makes them differ.
#>
[CmdletBinding()]
param(
  [string]$Exe         = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$BaselineExe = '',
  [string]$WorkDir     = "$env:TEMP\drag-lint-exception-facts-$PID"
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

function Compare-Exact([string[]]$Exp, [string[]]$Act) {
  $e = @($Exp); $a = @($Act)
  if ($e.Count -ne $a.Count) { return $false }
  for ($i = 0; $i -lt $e.Count; $i++) { if ($e[$i] -cne $a[$i]) { return $false } }
  return $true
}
function Get-Facts([string]$EngineExe, [string]$Db, [string[]]$Sel) {
  $raw = (& $EngineExe exception-facts @Sel --db $Db --json 2>$null) -join "`n"
  return ($raw | ConvertFrom-Json)
}
function Show($F) {
  return @($F.facts | ForEach-Object { '{0}|{1}|{2}|{3}|{4}|{5}' -f $_.action, $_.type, $_.type_qname, $_.via, $_.line, $_.col })
}

$db = Join-Path $WorkDir 'facts.sqlite'
$null = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

# A. one routine, exact, in source order
$stamp = Get-Facts $Exe $db @('--target', 'TypeFacts.Stamp')
$act = Show $stamp
$exp = @(
  'handles|ELocal|TypeFacts.ELocal|bound|27|11',
  'raises-expr|ELocal|TypeFacts.ELocal|handler|27|27',
  'handles|EDup|ExcA.EDup|bound|28|11',
  'raises-expr|Exception||local|28|25',
  'handles|EAbort||spelled|29|8',
  'reraises|EAbort||handler|29|18',
  'handles|EConvertError||spelled|30|11',
  'handles-all||||34|7',
  'reraises|||unknown|35|9',
  'handles|EArgumentException||spelled|38|11',
  'reraises|EArgumentException||handler|41|9',
  'handles|EOnlyA|ExcA.EOnlyA|bound|43|12',
  'handles-all||||46|3',
  'reraises|||unknown|47|5')
Check "A. --target TypeFacts.Stamp: exact rows ($($exp.Count))" (Compare-Exact $exp $act) ("actual=" + ($act -join '; '))
Check 'A. count field equals the rows' ($stamp.count -eq $exp.Count) "count=$($stamp.count)"
Check 'A. routine and file on every row' (@($stamp.facts | Where-Object { $_.routine -cne 'TypeFacts.Stamp' -or $_.file -notlike '*TypeFacts.pas' }).Count -eq 0)
$tail = Get-Facts $Exe $db @('--target', 'Stamp')
Check 'A. the trailing part selects the same rows' (Compare-Exact $exp (Show $tail))
$local = Show (Get-Facts $Exe $db @('--target', 'OutsideHandler'))
Check 'A. raise E outside a handler: the param type, via=local' (Compare-Exact @('raises-expr|ELocal|TypeFacts.ELocal|local|53|9') $local) ($local -join '; ')

# B. one type
$byT = Get-Facts $Exe $db @('--name', 'ELocal')
$rows = @($byT.facts | ForEach-Object { '{0}|{1}|{2}' -f $_.action, $_.routine, $_.line })
$expT = @('raises|TypeFacts.Thrower|16', 'raises-expr|TypeFacts.OutsideHandler|53', 'handles|TypeFacts.Stamp|27', 'raises-expr|TypeFacts.Stamp|27')
Check 'B. --name ELocal: raise, handler, handler-var raise, param raise' (Compare-Exact @($expT | Sort-Object) @($rows | Sort-Object)) ($rows -join '; ')
$ab = @((Get-Facts $Exe $db @('--name', 'EAbort')).facts | ForEach-Object { $_.action })
Check 'B. --name EAbort: the handler and its stamped reraise' (Compare-Exact @('handles', 'reraises') $ab) ($ab -join ',')
$dupBare = @((Get-Facts $Exe $db @('--name', 'EDup')).facts | ForEach-Object { $_.type_qname } | Sort-Object)
Check 'B. bare --name EDup lists both types' (Compare-Exact @('ExcA.EDup', 'ExcB.EDup') $dupBare) ($dupBare -join ',')
$dupQ = @((Get-Facts $Exe $db @('--name', 'ExcB.EDup')).facts | ForEach-Object { $_.routine })
Check 'B. qualified --name ExcB.EDup picks one' (Compare-Exact @('TypeFactsB.ThrowB') $dupQ) ($dupQ -join ',')
$exc = @((Get-Facts $Exe $db @('--name', 'Exception')).facts | ForEach-Object { $_.routine })
Check 'B. no ancestry: --name Exception lists its own sites, not the raisers of its descendants' (@($exc | Where-Object { $_ -in 'TypeFacts.Thrower', 'TypeFactsB.ThrowB' }).Count -eq 0) ($exc -join ',')

# C. text
$txt = (& $Exe exception-facts --target TypeFacts.Thrower --db $db 2>$null) -join "`n"
Check 'C. text: the action, the type, the via, the count' (($txt -match 'raises\s+TypeFacts\.ELocal\s+bound\s+TypeFacts\.Thrower') -and ($txt -match '1 exception fact')) $txt

# D. usage
$null = & $Exe exception-facts --db $db 2>&1
Check 'D. neither selector exits 2' ($LASTEXITCODE -eq 2) "exit=$LASTEXITCODE"
$null = & $Exe exception-facts --target A --name B --db $db 2>&1
Check 'D. both selectors exit 2' ($LASTEXITCODE -eq 2) "exit=$LASTEXITCODE"
$null = & $Exe exception-facts --target A --db (Join-Path $WorkDir 'none.sqlite') 2>&1
Check 'D. a missing DB exits non-zero' ($LASTEXITCODE -ne 0) "exit=$LASTEXITCODE"

# E. controls
Check 'E. control: the compare FAILS on the set minus one row' (-not (Compare-Exact @($exp | Select-Object -Skip 1) $act))
$empty = Get-Facts $Exe $db @('--target', 'NoSuchRoutine')
Check 'E. an empty answer: exit 0, count 0' (($LASTEXITCODE -eq 0) -and ($empty.count -eq 0)) "exit=$LASTEXITCODE count=$($empty.count)"

# F. the fact is what the answer stands on
if ($BaselineExe -ne '') {
  $BaselineExe = (Resolve-Path $BaselineExe).Path
  $db0 = Join-Path $WorkDir 'baseline.sqlite'
  $null = & $BaselineExe index $work --db $db0 2>&1
  $old = Get-Facts $Exe $db0 @('--target', 'TypeFacts.Stamp')
  Check 'F. a DB without the fact: the same site count' ($old.count -eq $exp.Count) "count=$($old.count)"
  $oldShow = Show $old
  Check 'F. a DB without the fact: the reraise reads unknown' ($oldShow -ccontains 'reraises|||unknown|29|18') ($oldShow -join '; ')
  Check 'F. a DB without the fact: nothing reads bound' (@($old.facts | Where-Object { $_.via -eq 'bound' }).Count -eq 0)
}

if ($script:Failed) { Write-Host 'run_exception_facts: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_exception_facts: PASS' -ForegroundColor Green
exit 0
} catch {
  Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
  exit 2
}
