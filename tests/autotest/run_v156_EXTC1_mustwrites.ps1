<#
  run_v156_EXTC1_mustwrites.ps1 -- 1.56 lane EXT-C1 (B5): must-write facts per routine.

  Indexes tests\fixtures\v156-extc1\uMustWrites.pas into a scratch DB and reads
  symbol_facts.must_writes of every routine through `sql --json` (rows are POSITIONAL arrays;
  mapped onto columns[].name below; a missing column makes the helper return nothing, which FAILS).

  must_writes = what the routine writes on EVERY path that returns normally: `Result`, a var / out
  parameter, an own field; comma separated, in first-write order; '' = none proven.

  Every proven case has an unproven twin in the fixture (one construct apart), so a stub engine
  that writes '' everywhere fails the proven half and one that lists every written name fails the
  unproven half:
    proven     Create, Always, BothBranches, ExitValue, RaisePath, TryExceptBoth, TryFinally,
               Loops (repeat), SelfDot, Shadow (FB), Partial (pVar), Lambda (FB), CaseElse,
               AfterSwallow, OldStyle, FreeOut
    unproven   Conditional (FA), EarlyExit, TryExceptBody, Swallow, Loops (while), NilWrite,
               SelfDot (FOther.FA), Shadow (local FA), WithOpaque, Partial (pRec.X, pVal),
               Lambda (FA), CaseNoElse, FreeOutMaybe
  Positive control: run with -Exe <the engine of lane/v156-w1base> -- every "proven" check FAILS
  (the column exists and is empty).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_v156_EXTC1_mustwrites: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path $Exe)) { Write-Host "run_v156_EXTC1_mustwrites: no engine at $Exe" -ForegroundColor Red; exit 2 }
$fxSrc = Join-Path $repo 'tests\fixtures\v156-extc1'
$work  = Join-Path $env:TEMP ('dl-v156-extc1-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null

$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name  $Detail" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}

# One SELECT -> array of PSCustomObject (columns by name). A failed query returns an EMPTY array.
function Lane-Sql([string]$Db, [string]$Query) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe sql --query $Query --db $Db --json 2>$null }
  if ($LASTEXITCODE -ne 0 -or -not $raw) { return }
  try { $j = ($raw -join "`n") | ConvertFrom-Json | ForEach-Object { $_ } } catch { return }
  $cols = @($j.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
  $out = New-Object System.Collections.Generic.List[object]
  foreach ($r in @($j.rows)) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $r[$i] }
    $out.Add([pscustomobject]$o)
  }
  return $out.ToArray()
}

Write-Host "run_v156_EXTC1_mustwrites: engine $Exe" -ForegroundColor Cyan

$fx = Join-Path $work 'fx'; Copy-Item -Recurse $fxSrc $fx
$db = Join-Path $work 'fx.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $fx --db $db *> (Join-Path $work 'index.log') }
$rc = $LASTEXITCODE

$rows = @(Lane-Sql $db "SELECT s.name AS n, COALESCE(f.must_writes, '') AS mw FROM symbol_facts f JOIN symbols s ON s.id = f.symbol_id ORDER BY s.name")
$got = @{}
foreach ($r in $rows) { $got[[string]$r.n] = [string]$r.mw }
Check 'VACUITY the fixture was indexed and its routines have facts rows' (($rc -eq 0) -and ($rows.Count -ge 24)) "(rc $rc, rows $($rows.Count))"

# routine name -> expected must_writes
$expect = [ordered]@{
  'Create'        = 'FA,FObj'
  'Always'        = 'FA,pOut,Result'
  'Conditional'   = 'Result'
  'BothBranches'  = 'FA,Result'
  'EarlyExit'     = ''
  'ExitValue'     = 'Result'
  'RaisePath'     = 'FA'
  'TryExceptBody' = ''
  'TryExceptBoth' = 'FA'
  'Swallow'       = ''
  'TryFinally'    = 'FA,FB'
  'Loops'         = 'FB'
  'NilWrite'      = ''
  'SelfDot'       = 'FA'
  'Shadow'        = 'FB'
  'WithOpaque'    = ''
  'Partial'       = 'pVar'
  'Lambda'        = 'FB'
  'CaseNoElse'    = ''
  'CaseElse'      = 'FA'
  'AfterSwallow'  = 'FA'
  'OldStyle'      = 'Result'
  'FreeOut'       = 'pOut'
  'FreeOutMaybe'  = ''
}
foreach ($k in $expect.Keys) {
  $has = $got.ContainsKey($k)
  $val = if ($has) { $got[$k] } else { '<no facts row>' }
  Check ("must_writes of {0} = '{1}'" -f $k, $expect[$k]) ($has -and ($val -ceq $expect[$k])) "(got '$val')"
}

if (-not $KeepScratch) { try { [IO.Directory]::Delete($work, $true) } catch { } } else { Write-Host "scratch: $work" }
Write-Host ("run_v156_EXTC1_mustwrites: {0} pass, {1} fail" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
exit $(if ($script:fail) { 1 } else { 0 })
