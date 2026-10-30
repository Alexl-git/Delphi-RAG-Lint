<#
  run_index_lock_released_before_warm.ps1 -- the one-writer lock (PR #7) is given
  back when the WRITES end, not when the process exits (whole-branch review, 1.39).

  THE DEFECT. `index --project` holds `<db>.indexing.lock` and then, in the
  default `--rule-cache-warm wait` (PR #1), warms the `lint <file>` rule cache in
  the same process -- minutes on a large project (252 s measured on 2,218 files).
  The warm only READS, but the lock was held to process exit, so an IDE
  save-reindex, an agent reindex or a rename's project refresh of the same
  database exited 2 ("another index run is writing") all that time.

  The runner stretches the warm window with the test hook
  DRAGLINT_TEST_WARM_DELAY_MS (a sleep before the wait-mode warm) and plays the
  second run inside it.

  WHAT THIS ASSERTS
    0. CONTROL: run A is still running when the checks below are made (inside
       the warm window, not after it)
    1. the lock file is gone while run A is still warming            <- THE FIX
    2. a second `index` on the same database exits 0, not 2          <- THE FIX
    3. CONTROL: run A itself ends with exit 0

  RED-CHECK: against the build before the fix 1 and 2 FAIL (the lock lives until
  A exits; the second run exits 2); 0 and 3 pass on both builds.
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

$work = Join-Path C:\TEMP "draglint_idxlock_warm_$PID"
[void][System.IO.Directory]::CreateDirectory($work)
$dir = Join-Path $work 'p'
Write-Ascii (Join-Path $dir 'Warm.dpr') @'
program Warm;

uses
  UWarm in 'UWarm.pas';

begin
end.
'@
Write-Ascii (Join-Path $dir 'UWarm.pas') @'
unit UWarm;

interface

procedure Touch;

implementation

procedure Touch;
begin
end;

end.
'@
$dpr = Join-Path $dir 'Warm.dpr'
$db = Join-Path $work 'warm.sqlite'
$lockPath = $db + '.indexing.lock'

Write-Host '=== run A: index, then a 20 s pause before the wait-mode warm ===' -ForegroundColor Cyan
$env:DRAGLINT_TEST_WARM_DELAY_MS = '20000'
try {
  $a = Start-Process -FilePath $Exe -ArgumentList @('index', '--project', "`"$dpr`"", '--db', "`"$db`"", '--rule-cache-warm', 'wait') `
    -WorkingDirectory $work -RedirectStandardOutput (Join-Path $work 'a.out') -RedirectStandardError (Join-Path $work 'a.err') `
    -NoNewWindow -PassThru
} finally { Remove-Item Env:\DRAGLINT_TEST_WARM_DELAY_MS -ErrorAction SilentlyContinue }

# The lock appears when A starts writing; with the fix it goes when the writes end.
$sawLock = $false; $released = $false
$deadline = (Get-Date).AddSeconds(15)
# released = the database exists, A is still running and its lock file is gone
while ((Get-Date) -lt $deadline -and -not $a.HasExited) {
  if (Test-Path -LiteralPath $lockPath) { $sawLock = $true }
  elseif (Test-Path -LiteralPath $db) { $released = $true; break }
  Start-Sleep -Milliseconds 100
}
$aliveAtCheck = -not $a.HasExited
$b = $null
if ($aliveAtCheck) {
  $bOut = Join-Path $work 'b.log'
  cmd /c "`"$Exe`" index --project `"$dpr`" --db `"$db`" --rule-cache-warm off > `"$bOut`" 2>&1" | Out-Null
  $b = @{ Code = $LASTEXITCODE; Out = (Get-Content -LiteralPath $bOut -Raw) }
}
$aliveAfterB = -not $a.HasExited

Check '0. CONTROL: run A is still in its warm window during the checks' ($aliveAtCheck -and $aliveAfterB) "alive at check=$aliveAtCheck, after B=$aliveAfterB"
Check '1. the lock file is gone while A is still warming' ($released -and $aliveAtCheck) "sawLock=$sawLock released=$released"
$bCode = if ($b) { $b.Code } else { 'not run' }
Check '2. a second index on the same database exits 0 (not 2)' ($b -and $b.Code -eq 0) "exit=$bCode $(if ($b -and $b.Code -ne 0) { $b.Out.Trim() })"

if (-not $a.WaitForExit(90000)) { $a.Kill($true); throw 'run A did not end in 90 s' }
Check '3. CONTROL: run A ends with exit 0' ($a.ExitCode -eq 0) "exit=$($a.ExitCode)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
}
catch { Write-Host "[FAIL] harness: $_" -ForegroundColor Red; exit 1 }
finally {
  $w = Join-Path C:\TEMP "draglint_idxlock_warm_$PID"
  if (Test-Path -LiteralPath $w) { try { [System.IO.Directory]::Delete($w, $true) } catch { } }
}
