<#
  run_lsp_proxy_lifecycle_guard.ps1 -- `drag-lint lsp --proxy` must never leave
  its DelphiLSP child running, and must not outlive the client that spawned it.

  WHAT THIS PINS (spec 2026-08-18-lsp-merge-proxy-design.md, criteria 5, 6):

    5. WHEN the proxy exits for any reason, INCLUDING TerminateProcess, the
       child and its descendants SHALL be terminated
    6. WHEN the client process that launched the proxy exits, the proxy SHALL
       exit

  WHY CASE C IS THE ONLY ONE THAT PROVES ANYTHING. A graceful exit reaps the
  child even with no Job Object at all -- the relay closes the pipes on its way
  out and the child sees EOF. So a suite of cases A and B passes against a
  build with the whole lifecycle mechanism removed. Case C kills the proxy with
  TerminateProcess, which runs no cleanup code whatsoever: nothing but a
  kernel-level Job Object can reap the child from there.

  This is not a hypothetical failure. An orphaned drag-lint child holds the
  project index open, and the next reindex fails with "used by another
  process" -- a symptom that reads as a corrupt database rather than as a
  process nobody killed.

  The stub therefore runs in LINGER mode for cases B and C: it ignores the
  stdin EOF that a dying relay produces for free. Without that, killing the
  relay closes the pipes, the stub exits by itself, and the whole suite passes
  against a build with no Job Object -- proving only that Windows closes
  handles.

  RED PROOF (recorded 2026-08-18): run against the Task 1 build, which spawns
  the child with no Job Object. Case A passes, cases B and C FAIL with the stub
  still running after the relay is gone.
#>

[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$Stub    = "$PSScriptRoot\fixtures\lspproxy\Win64\Debug\LspStubServer.exe",
  [string]$WorkDir = "$env:TEMP\draglint_lspproxy_lifecycle"
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$n, [bool]$ok, [string]$d) {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

function Stub-Pids { @(Get-Process LspStubServer -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id) }

# Kills every stub left over from an earlier run. Without this a stray child
# from a previous FAILED case makes the next case look failed too, and the
# report then blames the wrong mechanism.
function Reset-Stubs {
  foreach ($sp in (Get-Process LspStubServer -ErrorAction SilentlyContinue)) {
    try { $sp.Kill() } catch { }
  }
  $deadline = (Get-Date).AddSeconds(5)
  while ((Stub-Pids).Count -gt 0 -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100 }
}

# Starts the relay against the stub, with stdin/stdout redirected so the child
# has something to talk to, and waits until the stub is actually up. Returns the
# proxy Process plus the child pid, or $null for the child if it never appeared.
function Start-Relay {
  param([string[]]$extraArgs = @(), [switch]$Linger)

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  foreach ($a in (@('lsp','--proxy','--delphi-lsp',$Stub) + $extraArgs)) { [void]$psi.ArgumentList.Add($a) }
  $psi.RedirectStandardInput  = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute        = $false
  $psi.CreateNoWindow         = $true
  # Inherited by the stub through the relay. See LspStubServer.dpr: without
  # linger, the stub exits on the stdin EOF that killing the relay produces
  # anyway, and cases B and C would pass with no Job Object at all.
  if ($Linger) { $psi.Environment['DRAGLINT_STUB_LINGER'] = '1' }

  $before = Stub-Pids
  $p = [System.Diagnostics.Process]::Start($psi)

  $childPid = $null
  $deadline = (Get-Date).AddSeconds(10)
  while ((Get-Date) -lt $deadline) {
    $new = @(Stub-Pids | Where-Object { $_ -notin $before })
    if ($new.Count -gt 0) { $childPid = $new[0]; break }
    Start-Sleep -Milliseconds 100
  }
  return [pscustomobject]@{ Proxy = $p; ChildPid = $childPid }
}

function Wait-Gone([int]$procPid, [int]$timeoutMs = 8000) {
  $deadline = (Get-Date).AddMilliseconds($timeoutMs)
  while ((Get-Date) -lt $deadline) {
    if (-not (Get-Process -Id $procPid -ErrorAction SilentlyContinue)) { return $true }
    Start-Sleep -Milliseconds 100
  }
  return $false
}

Write-Host 'run_lsp_proxy_lifecycle_guard -- the relay never orphans DelphiLSP' -ForegroundColor Cyan

foreach ($need in @($Exe, $Stub)) {
  if (-not (Test-Path $need)) {
    Write-Host "FATAL: not found -- $need" -ForegroundColor Red
    Write-Host '(the stub is built by run_lsp_proxy_relay_guard.ps1; run that first)' -ForegroundColor Yellow
    Write-Host 'FAIL' -ForegroundColor Red
    exit 1
  }
}

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

# ---- CASE A: a normal exit reaps the child --------------------------------
Write-Host ''
Write-Host 'CASE A: the relay exits normally -> child gone' -ForegroundColor Cyan
Reset-Stubs
$a = Start-Relay
Check 'the child was spawned' ($null -ne $a.ChildPid) "child pid: $($a.ChildPid)"
if ($a.ChildPid) {
  # Closing our stdin ends the session the way a client shutting down does.
  $a.Proxy.StandardInput.Close()
  $proxyGone = $a.Proxy.WaitForExit(10000)
  Check 'the relay exited'    $proxyGone                    "exited: $proxyGone"
  Check 'the child is gone'   (Wait-Gone $a.ChildPid)       "pid $($a.ChildPid)"
}

# ---- CASE B: the client dies -> the relay follows it down ------------------
Write-Host ''
Write-Host 'CASE B: --parent-pid client exits -> relay exits -> child gone' -ForegroundColor Cyan
Reset-Stubs
# A throwaway stand-in for the IDE. The relay is NOT its child -- --parent-pid
# watches a pid, which is what the plugin passes and what must be honoured.
$fakeClient = Start-Process pwsh -ArgumentList '-NoProfile','-Command','Start-Sleep -Seconds 120' -PassThru -WindowStyle Hidden
$b = Start-Relay @('--parent-pid', "$($fakeClient.Id)") -Linger
Check 'the child was spawned' ($null -ne $b.ChildPid) "child pid: $($b.ChildPid)"
if ($b.ChildPid) {
  $fakeClient.Kill()
  Check 'the relay exited when its client died' (Wait-Gone $b.Proxy.Id 15000) "proxy pid $($b.Proxy.Id)"
  Check 'the child is gone'                     (Wait-Gone $b.ChildPid 15000) "pid $($b.ChildPid)"
}
try { if (-not $fakeClient.HasExited) { $fakeClient.Kill() } } catch { }

# ---- CASE C: THE ONE THAT MATTERS -----------------------------------------
Write-Host ''
Write-Host 'CASE C: the relay is KILLED (TerminateProcess) -> child STILL gone' -ForegroundColor Cyan
Reset-Stubs
$c = Start-Relay -Linger
Check 'the child was spawned' ($null -ne $c.ChildPid) "child pid: $($c.ChildPid)"
if ($c.ChildPid) {
  # .NET Process.Kill() is TerminateProcess: no finally blocks, no finalization,
  # no cleanup code of ours runs at all. Only the OS can reap the child now.
  $c.Proxy.Kill()
  Check 'the relay is gone' (Wait-Gone $c.Proxy.Id) "proxy pid $($c.Proxy.Id)"
  $childReaped = Wait-Gone $c.ChildPid 10000
  Check 'the child was reaped by the OS, not by our cleanup code' $childReaped `
    $(if ($childReaped) { "pid $($c.ChildPid)" } else { "ORPHANED: pid $($c.ChildPid) is still running -- no kill-on-close job object" })
}

Reset-Stubs
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
