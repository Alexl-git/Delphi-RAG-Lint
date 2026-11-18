<#
  run_check_init_intra.ps1 -- `check-init` lane HBINTRA (1.52): must-analysis inside ONE routine.

  Plan: docs\superpowers\plans\2026-11-17-happens-before-phase1.md, lane INTRA; spec
  docs\superpowers\specs\2026-11-17-happens-before-design.md sec. 5.3.

  Drives DRagLint.Query.HappensBefore.Intra.SolveRoutine directly through a small test driver
  (tests\fixtures\happens-before\intra-driver\IntraDriver.dpr, compiled here with dcc64): the
  `--explain --json` `.intra` view the plan names needs lane HBSOLVER's CheckInit, which does not
  exist yet (HANDOVER in the lane report). The fixture
  tests\fixtures\happens-before\intra-shapes\IntraShapes.pas has one routine per CFG shape, as
  twins (the mark dominates the query / it does not); the TRUTH TABLE below is exact:
    per routine: exit=<bit at normal exit> skipped=<cfg refused> q=<one letter per query site,
    T / F, suffix c when the site is inside an anonymous-method body>.
  Controls:
    * positive: --entry-done turns StraightNoDom's query T (the entry state reaches the query),
    * vacuity: every query must be located=T (a site the solver never matched would read F and
      make every NoDom twin pass for free),
    * comparator: a table with one flipped letter must FAIL the comparison.
  RED first on the FRAME/stub body (every query F): every *Dom twin fails.

  Parameters:
    -Exe        engine used to index the fixture (default src\cli\Win64\Debug\drag-lint.exe)
    -Repo       repo root (default: two levels above this script)
    -WorkDir    scratch folder (deleted at the end)
    -SkipBuild  run the driver already in -WorkDir
#>
[CmdletBinding()]
param(
  [string]$Repo    = '',
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-check-init-intra-$PID",
  [switch]$SkipBuild
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
Write-Host '== check-init INTRA truth table ==' -ForegroundColor Cyan
if ($Exe -eq '') { $Exe = Join-Path $Repo 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path

# routine -> expected "exit=<T|F> skipped=<T|F> q=<letters>"
$Truth = [ordered]@{
  'StraightDom'              = 'exit=T skipped=F q=T'
  'StraightNoDom'            = 'exit=T skipped=F q=F'
  'IfElseDom'                = 'exit=T skipped=F q=T'
  'IfNoElseNoDom'            = 'exit=F skipped=F q=F'
  'CaseElseDom'              = 'exit=T skipped=F q=T'
  'CaseNoElseNoDom'          = 'exit=F skipped=F q=F'
  'WhileDom'                 = 'exit=F skipped=F q=T'
  'WhileNoDom'               = 'exit=F skipped=F q=F'
  'RepeatDom'                = 'exit=T skipped=F q=T'
  'RepeatNoDom'              = 'exit=F skipped=F q=F'
  'ForLiteralDom'            = 'exit=T skipped=F q=T'
  'ForNoDom'                 = 'exit=F skipped=F q=F'
  'TryFinallyAfterDom'       = 'exit=T skipped=F q=T'
  'TryFinallyInFinallyNoDom' = 'exit=T skipped=F q=F'
  'TryFinallyInFinallyDom'   = 'exit=T skipped=F q=T'
  'TryExceptAfterNoDom'      = 'exit=F skipped=F q=F'
  'TryExceptAfterDom'        = 'exit=T skipped=F q=T'
  'TryExceptInHandlerNoDom'  = 'exit=F skipped=F q=F'
  'TryExceptInHandlerDom'    = 'exit=T skipped=F q=T'
  'ExitBeforeMark'           = 'exit=F skipped=F q=T'
  'RaiseBeforeMark'          = 'exit=T skipped=F q=T'
  'AnonMarkInside'           = 'exit=F skipped=F q=F'
  'AnonMarkOutside'          = 'exit=T skipped=F q=Fc,T'
  'GotoRoutine'              = 'exit=F skipped=T q=F'
  'ShortCircuitNoDom'        = 'exit=F skipped=F q=F'
  'ShortCircuitDom'          = 'exit=T skipped=F q=T'
  'TernaryNoDom'             = 'exit=F skipped=F q=F'
  'TernaryCondDom'           = 'exit=T skipped=F q=T'
  'WithOpaqueNoDom'          = 'exit=F skipped=F q=F'
  'SameItemNoDom'            = 'exit=T skipped=F q=F'
}

# Parse driver output into routine -> actual row; also collect located flags.
function Parse-Driver([string[]]$Lines) {
  $rows = [ordered]@{}
  $q = @{}
  $located = @{}
  foreach ($l in $Lines) {
    if ($l -match '^ROUTINE (\S+) found=(\w) skipped=(\w) exit=(\w) exitReach=(\w)$') {
      $rows[$Matches[1]] = @{ found = $Matches[2]; skipped = $Matches[3]; exit = $Matches[4] }
      $q[$Matches[1]] = @()
    } elseif ($l -match '^QUERY (\S+) (\d+) (\d+):(\d+) done=(\w) located=(\w) closure=(\w)$') {
      $letter = $Matches[5] + $(if ($Matches[7] -eq 'T') { 'c' } else { '' })
      $q[$Matches[1]] += $letter
      $located["$($Matches[1])#$($Matches[2])"] = $Matches[6]
    }
  }
  $actual = [ordered]@{}
  foreach ($k in $rows.Keys) {
    $actual[$k] = 'exit={0} skipped={1} q={2}' -f $rows[$k].exit, $rows[$k].skipped, ($q[$k] -join ',')
  }
  return @{ Actual = $actual; Located = $located; Rows = $rows }
}

# Compare a truth table with an actual table; returns the list of mismatch descriptions.
function Compare-Table($Expected, $Actual) {
  $bad = @()
  foreach ($k in $Expected.Keys) {
    if (-not $Actual.Contains($k)) { $bad += "$k missing"; continue }
    if ($Actual[$k] -cne $Expected[$k]) { $bad += "$k expected [$($Expected[$k])] got [$($Actual[$k])]" }
  }
  foreach ($k in $Actual.Keys) { if (-not $Expected.Contains($k)) { $bad += "$k not in the truth table" } }
  return ,$bad
}

try {
  if ((Test-Path -LiteralPath $WorkDir) -and -not $SkipBuild) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
  $driverExe = Join-Path $WorkDir 'IntraDriver.exe'
  if (-not $SkipBuild) {
    $src = Join-Path $Repo 'src'
    $dirs = 'preprocess','core','context','diagnostics','doc','forms','index','lint','lsp','mcp','output','parser',
            'project','query','refactor','report','resolver','sql','storage','workspace','analysis','cli'
    $paths = (@($dirs | ForEach-Object { Join-Path $src $_ }) + (Join-Path $Repo 'third_party\delphi-tree-sitter')) -join ';'
    $dpr = Join-Path $Repo 'tests\fixtures\happens-before\intra-driver\IntraDriver.dpr'
    $dcu = Join-Path $WorkDir 'dcu'
    New-Item -ItemType Directory -Path $dcu -Force | Out-Null
    $bat = Join-Path $WorkDir 'b.bat'
    $blog = Join-Path $WorkDir 'build.log'
    $q = [char]34
    $batText = "@echo off`r`ncall ${q}C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat${q}`r`n" +
      "cd /D ${q}$WorkDir${q}`r`n" +
      "dcc64 -B -Q -NU${q}$dcu${q} -E${q}$WorkDir${q} -U${q}$paths${q} -I${q}$paths${q} " +
      "-NSSystem;Xml;Data;Datasnap;Web;Soap;Winapi;System.Win;Data.Win;Datasnap.Win;Web.Win;Soap.Win;Xml.Win " +
      "${q}$dpr${q}`r`necho BUILD_EXITCODE=%errorlevel%`r`n"
    [IO.File]::WriteAllText($bat, $batText, [Text.Encoding]::ASCII)
    Start-Process -FilePath cmd.exe -ArgumentList ('/c ' + $q + $q + $bat + $q + ' > ' + $q + $blog + $q + ' 2>&1' + $q) -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    if (($bl -notmatch 'BUILD_EXITCODE=0') -or ($bl -match 'Error: |Fatal: ')) {
      Select-String -LiteralPath $blog -Pattern 'Error: |Fatal: ' | Select-Object -First 10 | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
      Write-Host "CHECK-INIT INTRA: FAIL -- the driver did not build (log: $blog)" -ForegroundColor Red
      exit 1
    }
    # The driver loads tree-sitter + sqlite from its own folder.
    foreach ($dll in 'sqlite3.dll','tree-sitter.dll','tree-sitter-delphi13.dll') {
      $from = Join-Path (Split-Path $Exe) $dll
      if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination $WorkDir -Force }
    }
  }
  if (-not (Test-Path -LiteralPath $driverExe)) { Write-Host "FATAL: driver not found: $driverExe" -ForegroundColor Red; exit 2 }

  # Index a private copy of the fixture (never a real project DB).
  $fix = Join-Path $WorkDir 'fixture'
  New-Item -ItemType Directory -Path $fix -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $Repo 'tests\fixtures\happens-before\intra-shapes\IntraShapes.pas') -Destination $fix -Force
  $unit = Join-Path $fix 'IntraShapes.pas'
  $db = Join-Path $WorkDir 'intra.sqlite'
  $null = & $Exe index $fix --db $db 2>&1
  Check 'fixture indexes (exit 0)' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

  $raw = @(& $driverExe --db $db --file $unit 2>&1 | ForEach-Object { "$_" })
  $code = $LASTEXITCODE
  Write-Host '  -- raw driver output --'
  $raw | ForEach-Object { Write-Host "    $_" }
  Check 'driver exit 0' ($code -eq 0) "exit=$code"
  $p = Parse-Driver $raw

  $mis = Compare-Table $Truth $p.Actual
  foreach ($m in $mis) { Check 'truth table' $false $m }
  Check ("truth table: {0} routines exact" -f $Truth.Count) ($mis.Count -eq 0) "mismatches=$($mis.Count)"

  $notFound = @($p.Rows.Keys | Where-Object { $p.Rows[$_].found -ne 'T' })
  Check 'every routine found (defProc located)' ($notFound.Count -eq 0) ($notFound -join ',')
  # A refused CFG (skipped=T) answers F without matching items; every other query must match one.
  $unloc = @($p.Located.Keys | Where-Object { ($p.Located[$_] -ne 'T') -and ($p.Rows[($_ -split '#')[0]].skipped -ne 'T') } | Sort-Object)
  Check 'vacuity control: every query located' (($p.Located.Count -gt 0) -and ($unloc.Count -eq 0)) ($unloc -join ',')

  # Positive control: the entry state reaches the query.
  $pc = @(& $driverExe --db $db --file $unit --only StraightNoDom --entry-done 2>&1 | ForEach-Object { "$_" })
  $pcq = $pc | Where-Object { $_ -match '^QUERY StraightNoDom 1 ' }
  Check 'positive control: --entry-done makes StraightNoDom q=T' ($pcq -match 'done=T') "$pcq"

  # Comparator control: one flipped letter must be caught.
  $flipped = [ordered]@{}
  foreach ($k in $Truth.Keys) { $flipped[$k] = $Truth[$k] }
  $flipped['StraightDom'] = 'exit=T skipped=F q=F'
  $fm = Compare-Table $flipped $p.Actual
  Check 'comparator control: a flipped row is reported' ($fm.Count -ge 1) "mismatches=$($fm.Count)"

  if ($script:Failed) { Write-Host 'CHECK-INIT INTRA: FAIL' -ForegroundColor Red; exit 1 }
  Write-Host 'CHECK-INIT INTRA: PASS' -ForegroundColor Green
  exit 0
} finally {
  if ((-not $SkipBuild) -and (Test-Path -LiteralPath $WorkDir) -and (-not $env:HB_KEEP_WORK)) {
    try { [IO.Directory]::Delete($WorkDir, $true) } catch { }
  }
}
