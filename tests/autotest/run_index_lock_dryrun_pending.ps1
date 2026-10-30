<#
  run_index_lock_dryrun_pending.ps1 -- two edges of the one-writer lock
  (PR #7 review, 2026-10-30).

  A. `index --dry-run` writes nothing (an in-memory store), so it must not take
     `<db>.indexing.lock`: a dry look beside a live writer is legitimate. With
     PR #7 as submitted it exited 2 "another index run is writing".
  B. A lock file whose delete is PENDING (the holder just exited and the OS has
     not finished deleting it) answers CreateFile with ACCESS_DENIED. PR #7
     reported that as "cannot create the lock file ... Access is denied", which
     reads like a permissions problem. The run now retries for a moment and, if
     the file is still on its way out, says another run is just finishing.

  WHAT THIS ASSERTS
    0. CONTROL: lock held -> plain `index --project` exits 2 (the lock works)
    1. lock held -> `index --project --dry-run` exits 0                <- THE FIX
    2. lock held -> the dry run did not create the database
    3. delete pending, never released -> exit 2 naming a run that is
       finishing, not "cannot create the lock file"                   <- THE FIX
    4. CONTROL: delete pending, released after 300 ms -> exit 0 (retry window)

  RED-CHECK: on the PR #7 build 1 and 3 FAIL; 0, 2 and 4 pass on both
  (4 can pass on the PR build when the engine starts slower than 300 ms).
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
$work = Join-Path C:\TEMP "draglint_idxlock2_$PID"
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

function New-PendingDelete([string]$path) {
  $scanner = [System.IO.File]::Open($path, 'OpenOrCreate', 'ReadWrite', 'ReadWrite, Delete')
  $holder = New-Object System.IO.FileStream($path, 'Open', 'ReadWrite', 'ReadWrite, Delete', 4096, [System.IO.FileOptions]::DeleteOnClose)
  $holder.Dispose()
  return $scanner
}

New-Item -ItemType Directory $work -Force | Out-Null
$dir = Join-Path $work 'p'
Write-Ascii (Join-Path $dir 'Lock2.dpr') @'
program Lock2;

uses
  ULock2 in 'ULock2.pas';

begin
end.
'@
Write-Ascii (Join-Path $dir 'ULock2.pas') @'
unit ULock2;

interface

procedure Touch;

implementation

procedure Touch;
begin
end;

end.
'@
$dpr = Join-Path $dir 'Lock2.dpr'
$db = Join-Path $work 'fresh.sqlite'
$lockPath = $db + '.indexing.lock'

Write-Host '=== A. another run holds the lock ===' -ForegroundColor Cyan
$held = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
try {
  $r0 = Run @('index', '--project', $dpr, '--db', $db)
  Check '0. CONTROL: plain index exits 2 while the lock is held' `
    (($r0.Code -eq 2) -and ($r0.Out -match 'another index run is writing')) "exit=$($r0.Code)"
  $r1 = Run @('index', '--project', $dpr, '--db', $db, '--dry-run')
  if ($r1.Code -ne 0) { Write-Host $r1.Out -ForegroundColor DarkGray }
  Check '1. index --dry-run is not refused by the lock (exit 0)' ($r1.Code -eq 0) "exit=$($r1.Code)"
  Check '2. the dry run did not create the database' (-not (Test-Path -LiteralPath $db)) ''
} finally {
  $held.Dispose()
  [System.IO.File]::Delete($lockPath)
}

Write-Host ''
Write-Host '=== B. the lock file is being deleted ===' -ForegroundColor Cyan
# A holder opened with DeleteOnClose closes while a third handle (a virus scanner,
# the search indexer) still has the file open with delete sharing: the file stays,
# delete-pending, until that handle closes. A plain File.Delete would not do: on
# Windows 10+ it unlinks the name at once (POSIX semantics) and nothing is pending.
$pend = New-PendingDelete $lockPath
try {
  $r3 = Run @('index', '--project', $dpr, '--db', $db)
  Write-Host $r3.Out -ForegroundColor DarkGray
  Check '3. pending delete: exit 2, says a run is finishing (not "cannot create")' `
    (($r3.Code -eq 2) -and ($r3.Out -match 'just finishing') -and ($r3.Out -notmatch 'cannot create the lock file')) "exit=$($r3.Code)"
} finally {
  $pend.Dispose()
}

$pend = New-PendingDelete $lockPath
$outB = Join-Path $work 'o-b4.log'
$p = Start-Process -FilePath $Exe -ArgumentList @('index', '--project', "`"$dpr`"", '--db', "`"$db`"") `
  -PassThru -NoNewWindow -RedirectStandardOutput $outB -RedirectStandardError ($outB + '.err')
Start-Sleep -Milliseconds 300
$pend.Dispose()
if (-not $p.WaitForExit(120000)) { $p.Kill(); Check '4. CONTROL: run finished in time' $false 'killed after 120 s' }
else { Check '4. CONTROL: pending delete released in the retry window -> exit 0' ($p.ExitCode -eq 0) "exit=$($p.ExitCode)" }

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path -LiteralPath $work) { [System.IO.Directory]::Delete($work, $true) }
}
