<#
  run_v154_SEARCHFAST.ps1 -- the `search` index stage (symbol_search + symbol_search_fts).

  WHAT IT PINS. The stage fell from 377 rows/s to 120 rows/s over 1.4 M rows:
  Migrate's one ANALYZE runs on an EMPTY database, where each FTS5 %_data table
  holds only its two seed rows, so sqlite_stat1 said "2 rows" for ever and the
  planner SCANNED %_data for every segment FTS5 dropped. The stage also wrote
  every row of a full re-parse through the sync triggers, one FTS5 flush each.

    ST  a fresh index leaves no tiny row count for an FTS5 %_data table, an old
        database carrying one is healed by the next writer, and the planner then
        seeks (control: with the count put back to 2 it scans)
    S1  an in-place forced full re-parse fills in one pass and ends with the same
        search rows, FTS5 content and triggers as a fresh build
    S2  a fill killed before its commit leaves the pre-stage state (no half
        index, a reader gets an answer or exit 3) and the next run completes it
    S3  a one-file edit goes through the triggers, rebuilds nothing, and still
        equals a fresh build
    S4  positive controls: the comparer sees one changed row, the FTS5 integrity
        check sees one unindexed row

  Scratch only; never a real project DB. Needs python on PATH.
  Usage: pwsh -File tests\autotest\run_v154_SEARCHFAST.ps1 [-Exe <drag-lint.exe>] [-WorkDir <dir>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = ''
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if (-not $WorkDir) { $WorkDir = Join-Path ([IO.Path]::GetTempPath()) ('dl_sf_' + [Guid]::NewGuid().ToString('N').Substring(0, 8)) }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "PASS  $Name  $Detail" }
  else { Write-Host "FAIL  $Name  $Detail" -ForegroundColor Red; $script:Failed = $true }
}
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path $Exe).Path
$Helper = Join-Path $PSScriptRoot 'searchfast_helper.py'

function Start-Exe([string[]]$ArgList, [hashtable]$EnvVars) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.Arguments = (($ArgList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  foreach ($k in $EnvVars.Keys) { $psi.EnvironmentVariables[$k] = [string]$EnvVars[$k] }
  return [System.Diagnostics.Process]::Start($psi)
}
function Run-Exe([string[]]$ArgList) {
  $p = Start-Exe $ArgList @{}
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  return @{ Code = $p.ExitCode; Out = $o.Result; Err = $e.Result }
}
function Index([string]$Db, [string[]]$More = @()) { return Run-Exe (@('index', $Src, '--db', $Db) + $More) }
function Py([string]$Verb, [string]$Db) {
  $out = & { $ErrorActionPreference = 'Continue'; & python -I $Helper $Verb $Db 2>&1 | ForEach-Object { "$_" } }
  return ($out -join "`n")
}
function Write-Unit([int]$No, [int]$Count, [string]$ExtraName) {
  $sb = New-Object System.Text.StringBuilder
  $null = $sb.Append("unit SearchUnit$No;`r`n`r`ninterface`r`n`r`n")
  $names = @(1..$Count | ForEach-Object { "HandleRow${No}Step$_" })
  if ($ExtraName) { $names += $ExtraName }
  foreach ($n in $names) { $null = $sb.Append("/// <summary>Walks the lantern of $n.</summary>`r`nprocedure $n;`r`n") }
  $null = $sb.Append("`r`nimplementation`r`n`r`n")
  foreach ($n in $names) { $null = $sb.Append("procedure $n;`r`nbegin`r`nend;`r`n`r`n") }
  $null = $sb.Append("end.`r`n")
  [IO.File]::WriteAllText((Join-Path $Src "SearchUnit$No.pas"), $sb.ToString(), [Text.Encoding]::ASCII)
}
# 'rebuilt:1203', 'patched:404', or 'none' (no row written).
function Filled($r) {
  $m = [regex]::Match($r.Err + $r.Out, 'search\s+(\d+) row\(s\) written, symbol_search_fts (rebuilt|patched)')
  if ($m.Success) { return $m.Groups[2].Value + ':' + $m.Groups[1].Value }
  return 'none'
}
$TinyRx = '=\d{1,3}(\s|$)'

try {
  $Src = Join-Path $WorkDir 'src'
  $null = New-Item -ItemType Directory -Force -Path $Src
  1..3 | ForEach-Object { Write-Unit $_ 400 '' }
  $db    = Join-Path $WorkDir 'inplace.sqlite'
  $fresh = Join-Path $WorkDir 'fresh.sqlite'

  # ---- ST: the recorded size of the FTS5 tables ----
  $r = Index $db
  Check 'control: the fixture indexes' ($r.Code -eq 0) "exit=$($r.Code)"
  if ($r.Code -ne 0) { throw "setup index failed: $($r.Err)" }
  $stat = Py 'stat' $db
  Check 'ST1 a fresh index records no tiny row count for an FTS5 data table' ($stat -notmatch $TinyRx) "stat=[$stat]"
  $plan = Py 'plan' $db
  Check 'ST2 the planner seeks in symbol_search_fts_data' ($plan -match '^SEARCH') $plan
  $null = Py 'poison' $db
  $plan = Py 'plan' $db
  Check 'ST3 control: a recorded count of 2 makes the planner scan' ($plan -match '^SCAN') $plan
  $r = Index $db
  $stat = Py 'stat' $db
  $plan = Py 'plan' $db
  Check 'ST4 the next writer heals a database that carries the count 2' (($r.Code -eq 0) -and ($stat -notmatch $TinyRx) -and ($plan -match '^SEARCH')) "exit=$($r.Code) stat=[$stat] $plan"

  # ---- S1: forced full re-parse in place == fresh ----
  $null = Index $fresh
  $want = Py 'dump' $fresh
  Check 'control: the fresh build is complete (1200 documented routines, FTS5 intact)' ($want -match 'hits=\[1200, 1200, 1, 0\] triggers=3 fts=intact') $want
  $r = Index $db @('--force-reparse')
  Check 'S1a the in-place full re-parse fills in one pass' ((Filled $r) -match '^rebuilt:12\d\d$') (Filled $r)
  $got = Py 'dump' $db
  Check 'S1b search rows, FTS5 content and triggers equal a fresh build' (($r.Code -eq 0) -and ($got -eq $want)) $got

  # ---- S2: killed before the commit ----
  $p = Start-Exe @('index', $Src, '--db', $db, '--force-reparse') @{ DRAGLINT_TEST_SEARCH_HOLD_MS = 60000 }
  $errTask = $p.StandardError.ReadToEndAsync()
  while ($null -ne ($line = $p.StandardOutput.ReadLine())) { if ($line -match 'stage: search -- started') { break } }
  Start-Sleep -Milliseconds 2500
  $held = -not $p.HasExited
  Check 'S2a the fill is held complete but uncommitted' $held
  $c0 = Py 'counts' $db
  Check 'S2b a reader beside it sees no half index (all rows with their FTS5 entry, or none)' ($c0 -match '^(0 0|12\d\d 12\d\d) 1200$') $c0
  $q = Run-Exe @('query', '--concept', 'lantern', '--db', $db)
  Check 'S2c query --concept beside it answers (0) or says not ready (3)' (@(0, 3) -contains $q.Code) "exit=$($q.Code)"
  if ($held) { $p.Kill() }
  $p.WaitForExit()
  $r = Index $db
  $got = Py 'dump' $db
  Check 'S2d the next run completes the fill: equal to a fresh build' (($r.Code -eq 0) -and ((Filled $r) -match '^rebuilt:') -and ($got -eq $want)) "exit=$($r.Code) fill=$(Filled $r) $got"
  $r = Index $db
  Check 'S2e a run after that writes no search row' (($r.Code -eq 0) -and ((Filled $r) -eq 'none')) (Filled $r)

  # ---- S3: one file ----
  Write-Unit 2 400 'PolishPelican'
  $r = Index $db
  Check 'S3a a one-file edit patches its own rows and rebuilds nothing' ((Filled $r) -match '^patched:(\d|\d\d|40\d)$') (Filled $r)
  $fresh2 = Join-Path $WorkDir 'fresh2.sqlite'
  $null = Index $fresh2
  $want2 = Py 'dump' $fresh2
  $got   = Py 'dump' $db
  Check 'S3b the search tables equal a fresh build of the edited sources' (($got -eq $want2) -and ($want2 -match 'hits=\[1201, 1200, 1, 1\]')) "got $got want $want2"

  # ---- S4: the comparer can fail ----
  Copy-Item -LiteralPath $fresh2 -Destination "$fresh2.c1"
  $null = Py 'changerow' "$fresh2.c1"
  $d = Py 'dump' "$fresh2.c1"
  Check 'S4a control: one changed row changes the dump' (($d -match '^rows=') -and ($d -ne $want2)) $d
  Copy-Item -LiteralPath $fresh2 -Destination "$fresh2.c2"
  $null = Py 'unindexed' "$fresh2.c2"
  $d = Py 'dump' "$fresh2.c2"
  Check 'S4b control: a search row missing behind the index breaks the integrity check' ($d -match 'fts=BROKEN') $d
}
catch {
  Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
  $script:Failed = $true
}
finally {
  try { if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) } } catch { }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host "ALL PASS ($($script:Pass))"
exit 0
