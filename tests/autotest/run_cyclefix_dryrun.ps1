<#
  run_cyclefix_dryrun.ps1 -- E18 Task 8: `cycles --fix` dry run (gate, verdicts, cycle-fix/1 JSON).

  Asserts, on a COPY of circular-demo:
    (a) `cycles --fix --project <copy>\CircularDemo.dproj --db <db> --no-compile --format json`
        -> exit 0, cycles[0].verdict = mechanical, part = a, 3 new_units, 18 edits
        (14 unit edits + 1 .dpr + 3 .dproj), schema cycle-fix/1, mode dry-run, every
        documented field present.
    (b) `--unit demogageport` (library copy) -> recipe member-interface,
        edge demouiconnect->demogageport.
    (c) `--fix` without `--project` -> exit 2.
    (d) a copy whose DemoLogger.pas was touched after indexing (blank line appended):
        `--cycle 1` -> exit 1, refusals[0].kind = stale-file.
    (e) POSITIVE CONTROL: `--format text` prints `Verdict:`; a refused group prints
        `Verdict: refused` and one `  - <kind>: ` line per refusal.
    (f) the dry run writes NOTHING: SHA-256 of every file of the copy and of its index DB
        is the same before and after every run above.

  THE PLATFORM LIBRARY: never opened in place. Copied into the $PID scratch dir and passed
  with --library-db; size + mtime of the real library DBs are compared before and after.
  Without the library DB on disk, check (b) is SKIPped. Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-dryrun-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite'
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Get-LibStamp {
  return (@(Get-ChildItem 'C:\Projects\.drag-lint' -Filter 'library-*.sqlite' -ErrorAction SilentlyContinue |
    Sort-Object Name | ForEach-Object { '{0}={1}@{2:o}' -f $_.Name, $_.Length, $_.LastWriteTimeUtc }) -join ' ')
}
function Get-TreeHash([string]$Dir, [string]$Db) {
  $files = @(Get-ChildItem $Dir -File -Recurse) + @(Get-Item $Db)
  return (($files | Sort-Object FullName | ForEach-Object { '{0}={1}' -f $_.Name, (Get-FileHash $_.FullName -Algorithm SHA256).Hash }) -join ';')
}
function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}
function Index-Copy([string]$Dir, [string]$Tag) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  $idx = & $Exe index --project (Join-Path $Dir 'CircularDemo.dproj') --db $db 2>&1 | Out-String
  Check "${Tag}: SANITY the 10 units indexed with 0 errors" `
    (([regex]::Matches($idx, 'Demo[\w.]+\.pas\s*->\s*\d+ symbols, \d+ refs, 0 errors')).Count -eq 10) $idx
  return $db
}
# `cycles --fix <extra>` on a copy; returns Exit + stdout text (+ parsed JSON when asked).
function Run-Fix([string]$Dir, [string]$Db, [string[]]$Extra, [bool]$Json = $true) {
  $a = @('cycles', '--fix', '--project', (Join-Path $Dir 'CircularDemo.dproj'), '--db', $Db) + $Extra
  if ($Json) { $a += @('--format', 'json') }
  $out = (& $Exe @a 2>$null | Out-String)
  $code = $LASTEXITCODE
  $j = $null
  if ($Json) { try { $j = $out | ConvertFrom-Json } catch { $j = $null } }
  return @{ Exit = $code; Out = $out; Json = $j }
}

$stampBefore = Get-LibStamp
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$haveLib = Test-Path $LibraryDb
$Lib = Join-Path $WorkDir 'library-copy.sqlite'
Push-Location $WorkDir
try {
  if ($haveLib) { Copy-Item $LibraryDb $Lib -Force }
  $demo = Join-Path $WorkDir 'demo'
  Copy-Tree (Join-Path $Repo 'circular-demo') $demo
  $db = Index-Copy $demo 'demo'
  $hashBefore = Get-TreeHash $demo $db

  Write-Host '== (a) default group: first mechanical' -ForegroundColor Cyan
  $r = Run-Fix $demo $db @('--no-compile', '--library-db', 'none')
  Check 'a: exit 0' ($r.Exit -eq 0) "exit $($r.Exit) out: $($r.Out)"
  $c = if ($r.Json) { $r.Json.cycles[0] } else { $null }
  Check 'a: schema cycle-fix/1, mode dry-run' ($r.Json -and $r.Json.schema -eq 'cycle-fix/1' -and $r.Json.mode -eq 'dry-run') $r.Out
  Check 'a: cycles[0].verdict = mechanical' ($c -and $c.verdict -eq 'mechanical') $r.Out
  Check 'a: cycles[0].part = a' ($c -and $c.part -eq 'a') $r.Out
  Check 'a: 3 new_units' ($c -and @($c.new_units).Count -eq 3) "got $(@($c.new_units).Count)"
  Check 'a: 18 edits' ($c -and @($c.edits).Count -eq 18) "got $(@($c.edits).Count)"
  $need = 'n','units','interface_edges','edges','part','verdict','recipe','edge','refusals','moves','uses','new_units','edits',
          'compile','baseline','repairs','written','backups','reindex','predicted','actual','verified'
  $have = if ($c) { @($c.PSObject.Properties.Name) } else { @() }
  Check 'a: every documented field is present' (@($need | Where-Object { $have -notcontains $_ }).Count -eq 0) `
    ('missing: ' + (@($need | Where-Object { $have -notcontains $_ }) -join ','))
  Check 'a: arrays are arrays (refusals/repairs/written/backups empty)' `
    ($c -and @($c.refusals).Count -eq 0 -and @($c.repairs).Count -eq 0 -and @($c.written).Count -eq 0 -and @($c.backups).Count -eq 0) $r.Out
  Check 'a: ok = true, exit_code = 0' ($r.Json -and $r.Json.ok -eq $true -and $r.Json.exit_code -eq 0) $r.Out

  Write-Host '== (b) --unit demogageport: member-interface' -ForegroundColor Cyan
  if ($haveLib) {
    $r = Run-Fix $demo $db @('--unit', 'demogageport', '--no-compile', '--library-db', $Lib)
    $c = if ($r.Json) { $r.Json.cycles[0] } else { $null }
    Check 'b: exit 0' ($r.Exit -eq 0) "exit $($r.Exit) out: $($r.Out)"
    Check 'b: recipe = member-interface' ($c -and $c.recipe -eq 'member-interface') $r.Out
    Check 'b: edge = demouiconnect->demogageport' ($c -and $c.edge -eq 'demouiconnect->demogageport') $r.Out
  } else { Write-Host '  SKIP b: no platform library DB on disk' -ForegroundColor Yellow }

  Write-Host '== (c) --fix without --project' -ForegroundColor Cyan
  $out = (& $Exe cycles --fix --db $db --library-db none 2>&1 | Out-String)
  Check 'c: exit 2' ($LASTEXITCODE -eq 2) "exit $LASTEXITCODE"
  Check 'c: names --project' ($out.Contains('cycles --fix needs --project <X.dproj>')) $out

  Write-Host '== (e) text output: positive control + a refused group' -ForegroundColor Cyan
  $r = Run-Fix $demo $db @('--no-compile', '--library-db', 'none') $false
  Check 'e: --format text contains Verdict:' ($r.Out -match 'Verdict: mechanical \(dry run; add --apply to write\)') $r.Out
  $r = Run-Fix $demo $db @('--cycle', '2', '--no-compile', '--library-db', 'none') $false
  Check 'e: refused group: exit 1' ($r.Exit -eq 1) "exit $($r.Exit)"
  Check 'e: refused group: Verdict: refused + a refusal line' `
    (($r.Out -match '(?m)^Verdict: refused') -and ($r.Out -match '(?m)^  - [\w-]+: ')) $r.Out
  Check 'e: --part b on an interface-coupled group is an error (exit 2)' `
    ((Run-Fix $demo $db @('--cycle', '1', '--part', 'b', '--library-db', 'none') $false).Exit -eq 2) ''
  Check 'e: --apply is refused today (exit 2)' `
    ((Run-Fix $demo $db @('--apply', '--library-db', 'none') $false).Exit -eq 2) ''

  Write-Host '== (f) the dry run wrote nothing' -ForegroundColor Cyan
  Check 'f: SHA-256 of every file of the copy and of its DB unchanged' ((Get-TreeHash $demo $db) -eq $hashBefore) ''

  Write-Host '== (d) stale-file' -ForegroundColor Cyan
  $stale = Join-Path $WorkDir 'stale'
  Copy-Tree (Join-Path $Repo 'circular-demo') $stale
  $sdb = Index-Copy $stale 'stale'
  Start-Sleep -Milliseconds 1100
  [IO.File]::AppendAllText((Join-Path $stale 'DemoLogger.pas'), "`r`n")
  $r = Run-Fix $stale $sdb @('--cycle', '1', '--no-compile', '--library-db', 'none')
  Check 'd: exit 1' ($r.Exit -eq 1) "exit $($r.Exit) out: $($r.Out)"
  Check 'd: refusals[0].kind = stale-file' ($r.Json -and $r.Json.cycles[0].refusals[0].kind -eq 'stale-file') $r.Out
  Check 'd: the stale refusal names DemoLogger.pas' ($r.Json -and $r.Json.cycles[0].refusals[0].file -like '*DemoLogger.pas') $r.Out
} finally {
  Pop-Location
}
Check 'z1: the real library DBs are unchanged (size + mtime)' ((Get-LibStamp) -eq $stampBefore) ''

Write-Host ("{0} PASS" -f $script:Passed)
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
