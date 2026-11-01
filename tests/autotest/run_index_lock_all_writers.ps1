<#
  run_index_lock_all_writers.ps1 -- every verb that WRITES the index takes
  <db>.indexing.lock like `index` does (1.40 IDX-LOCK; INBOX-139 #1).

  THE DEFECT. purge-locals, fb-snapshot, refresh-findings and reconcile-project --db
  opened the index for writing without the lock, so they could run beside an `index`
  of the same database and end in "database is locked" (or interleave rows). The MCP
  store is read-only since Gitea #34, so it needs no lock.

  This runner plays the other run by opening the lock file with FileShare.None.

  WHAT THIS ASSERTS (per verb)
    held : exit 2 and the text 'another index run'           <- THE FIX
    free : CONTROL (positive): the same call is NOT refused with that text
           (it may still fail for its own reasons, e.g. fb-snapshot has no Firebird)
    and no lock file is left behind.

  RED-CHECK: on the pre-fix build every 'held' check FAILs; every 'free' check passes.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
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
function Write-Ascii([string]$path, [string]$text) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir -Force | Out-Null }
  [System.IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
}
function Run([string[]]$ArgList) {
  $out = Join-Path $work ('o-{0}.log' -f [guid]::NewGuid().ToString('N').Substring(0,8))
  $quoted = ($ArgList | ForEach-Object { '"' + $_ + '"' }) -join ' '
  cmd /c "`"$Exe`" $quoted > `"$out`" 2>&1" | Out-Null
  $code = $LASTEXITCODE
  $o = if (Test-Path -LiteralPath $out) { Get-Content -LiteralPath $out -Raw } else { '' }
  if ($null -eq $o) { $o = '' }
  return @{ Out = $o; Code = $code }
}
$work = Join-Path C:\TEMP "draglint_idxlockall_$PID"
New-Item -ItemType Directory $work -Force | Out-Null
$dir = Join-Path $work 'p'
Write-Ascii (Join-Path $dir 'Lock.dpr') "program Lock;`nuses`n  ULock in 'ULock.pas';`nbegin`nend.`n"
Write-Ascii (Join-Path $dir 'ULock.pas') "unit ULock;`ninterface`nprocedure Touch;`nimplementation`nprocedure Touch;`nbegin`nend;`nend.`n"
$dpr = Join-Path $dir 'Lock.dpr'
$db = Join-Path $work 'w.sqlite'
$lockPath = $db + '.indexing.lock'
$seed = Run @('index', '--project', $dpr, '--db', $db)
Check 'seed: index built' ($seed.Code -eq 0) "exit=$($seed.Code)"

$verbs = [ordered]@{
  'purge-locals'      = @('purge-locals', '--db', $db)
  'fb-snapshot'       = @('fb-snapshot', '--connection', 'Database=nowhere.fdb;DriverID=FB', '--db', $db)
  'refresh-findings'  = @('refresh-findings', '--project', $dpr, '--db', $db)
  'reconcile-project' = @('reconcile-project', $dpr, '--db', $db)
}
foreach ($v in $verbs.Keys) {
  Write-Host "=== $v ===" -ForegroundColor Cyan
  $held = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
  try { $r = Run $verbs[$v] } finally { $held.Dispose(); Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue }
  Check "$v held: exit 2 + 'another index run'" (($r.Code -eq 2) -and ($r.Out -match 'another index run')) "exit=$($r.Code)"
  $f = Run $verbs[$v]
  Check "$v free: CONTROL not refused by the lock" ($f.Out -notmatch 'another index run') "exit=$($f.Code)"
  Check "$v free: CONTROL no lock file left" (-not (Test-Path -LiteralPath $lockPath)) ''
}

# --- CFG-DBREDIRECT: a cwd .drag-lint.json "db" must not pick the DB of a writing verb ---
Write-Host '=== cwd config db redirect ===' -ForegroundColor Cyan
$cwd = Join-Path $work 'cwd'
New-Item -ItemType Directory $cwd -Force | Out-Null
$victim = Join-Path $work 'victim.sqlite'
Copy-Item -LiteralPath $db -Destination $victim
Write-Ascii (Join-Path $cwd '.drag-lint.json') ('{"db": "' + $victim.Replace('\', '/') + '"}')
function RunIn([string]$dirIn, [string[]]$ArgList) {
  Push-Location $dirIn
  try { return (Run $ArgList) } finally { Pop-Location }
}
$before = (Get-Item -LiteralPath $victim).LastWriteTimeUtc
$cfgVerbs = [ordered]@{
  'purge-locals'      = @('purge-locals')
  'refresh-findings'  = @('refresh-findings', '--project', $dpr)
  'reconcile-project' = @('reconcile-project', $dpr)
}
foreach ($v in $cfgVerbs.Keys) {
  $r = RunIn $cwd $cfgVerbs[$v]
  Check "${v}: config db outside its tree refused (exit 2, names the key)" (($r.Code -eq 2) -and ($r.Out -match '"db" key')) "exit=$($r.Code)"
}
Check 'the victim DB was not written' ((Get-Item -LiteralPath $victim).LastWriteTimeUtc -eq $before) ''
$c = RunIn $cwd @('purge-locals', '--db', $victim)
Check 'CONTROL: the same verb with an explicit --db runs' ($c.Code -eq 0) "exit=$($c.Code)"
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  $d = Join-Path C:\TEMP "draglint_idxlockall_$PID"
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
}
