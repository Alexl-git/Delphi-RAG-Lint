<#
  run_index_concurrent_lock.ps1 -- a second `index` on a database another run
  is writing must be refused at the START (Gitea drag-lint#17).

  THE DEFECT. On 2026-10-09 two `index --project ... --rebuild` runs met on
  the ProjectA database. The second parsed all ~2,000 files and only then died
  with `FATAL: ESQLiteNativeException: ... database is locked` (exit 3); while
  the two overlapped the index answered with 2,034 of 2,224 files and its
  unit_uses unbound. Nothing checked for another writer before the work.

  The fix holds `<db>.indexing.lock` (no sharing, delete-on-close) for the
  whole run. This runner plays the other run by opening that file with
  FileShare.None, which is exactly what a live indexer holds.

  WHAT THIS ASSERTS
    1. lock held: `index --project` exits 2 and says another run is writing  <- THE FIX
    2. lock held: it refused BEFORE touching the database (no .sqlite made)  <- THE FIX
    3. CONTROL: a reader is not blocked -- query on an existing index works
       while the lock is held
    4. CONTROL: lock released: the same index runs (exit 0)
    5. CONTROL: and leaves no lock file behind (delete-on-close)

  RED-CHECK: against the pre-fix build 1 and 2 FAIL (it ignores the lock and
  indexes); 3, 4 and 5 pass on both builds.
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

$work = Join-Path C:\TEMP "draglint_idxlock_$PID"
if (Test-Path $work) { Get-ChildItem $work -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory $work -Force | Out-Null

$dir = Join-Path $work 'p'
Write-Ascii (Join-Path $dir 'Lock.dpr') @'
program Lock;

uses
  ULock in 'ULock.pas';

begin
end.
'@
Write-Ascii (Join-Path $dir 'ULock.pas') @'
unit ULock;

interface

procedure Touch;

implementation

procedure Touch;
begin
end;

end.
'@
$dpr = Join-Path $dir 'Lock.dpr'
$db = Join-Path $work 'fresh.sqlite'
$lockPath = $db + '.indexing.lock'

# An existing index for the reader control.
$dbRead = Join-Path $work 'read.sqlite'
$seed = Run @('index', '--project', $dpr, '--db', $dbRead)
Check 'seed: reader index built' ($seed.Code -eq 0) "exit=$($seed.Code)"

Write-Host ''
Write-Host '=== another run holds the lock ===' -ForegroundColor Cyan
$held = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
$readLock = [System.IO.File]::Open($dbRead + '.indexing.lock', 'OpenOrCreate', 'ReadWrite', 'None')
try {
  $r = Run @('index', '--project', $dpr, '--db', $db)
  Write-Host $r.Out -ForegroundColor DarkGray
  Check '1. index exits 2 and says another run is writing' `
    (($r.Code -eq 2) -and ($r.Out -match 'another index run is writing')) "exit=$($r.Code)"
  Check '2. it refused before touching the database' (-not (Test-Path -LiteralPath $db)) ''
  $q = Run @('query', '--name', 'Touch', '--db', $dbRead, '--exact')
  Check '3. CONTROL: a query is not blocked by the lock' (($q.Code -eq 0) -and ($q.Out -match 'ULock\.Touch')) "exit=$($q.Code)"
} finally {
  $held.Dispose()
  $readLock.Dispose()
  Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath ($dbRead + '.indexing.lock') -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host '=== lock released ===' -ForegroundColor Cyan
$ok = Run @('index', '--project', $dpr, '--db', $db)
Check '4. CONTROL: the same index runs once the lock is free' ($ok.Code -eq 0) "exit=$($ok.Code)"
Check '5. CONTROL: no lock file is left behind' (-not (Test-Path -LiteralPath $lockPath)) ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_idxlock_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
