<#
  run_closed_pipe_keeps_exit3.ps1 -- a reader that closes stdout early gets a
  NONZERO exit (owner ruling 2026-10-30 on outside PR #4).

  PR #4 proposed exit 0 when stdout is closed early (EInOutError 232/109, like a
  Unix tool on SIGPIPE). DECLINED: `lint x.pas | head` with findings would then
  exit 0, and a pipefail / CI step would read a truncated run as a clean one.
  Today's FATAL 3 stays. This guard pins it so the quiet-exit cannot return
  unnoticed.

  The reader here is a .NET Process that reads a few characters of stdout and
  closes the stream -- PowerShell's own `| Select-Object -First` stops the
  pipeline in a way that hides both the exit code and stderr.

  WHAT THIS ASSERTS
    1. `rules`, reader closes early: exit 3 (nonzero)        <- THE RULING
    2. `--help`, same                                         <- THE RULING
    3. CONTROL: read to the end, `rules` exits 0 with the whole list
    4. CONTROL: a real error keeps its code (missing --db -> exit 2)

  RED-CHECK: against PR #4's build (be8c2dd8) 1 and 2 FAIL (exit 0); on main
  and on this branch they pass. 3 and 4 pass on every build.#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
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

# Starts the exe, reads $Take chars of stdout (all of it when $Take -lt 0),
# closes stdout, and returns exit code, stderr and what was read.
function RunReader([string[]]$ArgList, [int]$Take) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.Arguments = ($ArgList | ForEach-Object { '"' + $_ + '"' }) -join ' '
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $errTask = $p.StandardError.ReadToEndAsync()
  if ($Take -lt 0) { $out = $p.StandardOutput.ReadToEnd() }
  else {
    $buf = New-Object char[] $Take
    $n = $p.StandardOutput.Read($buf, 0, $Take)
    $out = New-Object string ($buf, 0, $n)
    $p.StandardOutput.Close()
  }
  if (-not $p.WaitForExit(60000)) { $p.Kill(); return @{ Code = -1; Err = 'TIMEOUT'; Out = $out } }
  return @{ Code = $p.ExitCode; Err = $errTask.Result; Out = $out }
}

# Output must exceed the pipe buffer for the write to hit the closed pipe.
$full = RunReader @('rules') -1
Write-Host ("rules prints {0} chars" -f $full.Out.Length) -ForegroundColor DarkGray

Write-Host ''
Write-Host '=== case 1-2: reader closes stdout early ===' -ForegroundColor Cyan
$r = RunReader @('rules') 64
Check '1. rules: exit 3 (a truncated run is not a clean one)' ($r.Code -eq 3) "exit=$($r.Code) stderr=$($r.Err.Trim())"
$h = RunReader @('--help') 64
Check '2. --help: exit 3' ($h.Code -eq 3) "exit=$($h.Code) stderr=$($h.Err.Trim())"

Write-Host ''
Write-Host '=== case 3-4: CONTROLS ===' -ForegroundColor Cyan
Check '3. CONTROL: read to the end, rules exits 0 with a long list' `
  (($full.Code -eq 0) -and ($full.Out.Length -gt 8192)) "exit=$($full.Code) chars=$($full.Out.Length)"
$missing = Join-Path $env:TEMP ("draglint_nodb_{0}.sqlite" -f $PID)
$m = RunReader @('query', '--name', 'X', '--db', $missing) -1
Check '4. CONTROL: a missing --db still exits 2' ($m.Code -eq 2) "exit=$($m.Code)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
