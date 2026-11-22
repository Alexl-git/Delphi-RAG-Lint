#Requires -Version 7
# dl:serial: LSP proxy family. Spawns and kills DelphiLSP children; runs two proxy guards.
<#
  run_v1523_PROXY_child_killed.ps1 -- PROXY-KILLED (1.52.3): the owner's VS Code LSP
  "crash" of 2026-11-21 20:43 (exit 4294967295, restart dead before initialize).

  ROOT CAUSE. Not a drag-lint crash. Lane TESTS-ENV was running
  run_lsp_proxy_bits_guard.ps1 in a loop; its Reap() (and the same function in
  run_lsp_proxy_byte_identity_guard.ps1) killed EVERY DelphiLSP.exe on the machine,
  including the child of the owner's `lsp --proxy`. Process.Kill() is
  TerminateProcess(-1); the proxy relays the child's exit code before a shutdown
  request, so it exited -1 too, with nothing on stderr. The restart's new child was
  killed by the next loop's Reap.

  Checks:
    (A) relay: `lsp --proxy` with its DelphiLSP child killed mid-session (after
        initialize) exits -1 (positive control: the owner's 4294967295), and its
        stderr NAMES the child's code 0xFFFFFFFF and says it came before shutdown
        (the proxy used to be silent, so the cause looked like drag-lint's).
    (B) containment: a FOREIGN DelphiLSP (a decoy this script starts, standing in for
        the one under VS Code) survives run_lsp_proxy_bits_guard.ps1 and
        run_lsp_proxy_byte_identity_guard.ps1, and both guards still PASS.
  Skipped (not failed) without Studio's bin64\DelphiLSP.exe.
  -Exe defaults to the worktree Debug build; -BitsGuard / -IdentityGuard let a RED run
  point at the pre-fix guards. Run from a NEUTRAL CWD.
#>
[CmdletBinding()]
param(
  [string]$Exe           = '',
  [string]$Server        = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin64\DelphiLSP.exe',
  [string]$BitsGuard     = '',
  [string]$IdentityGuard = ''
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if (-not $BitsGuard) { $BitsGuard = "$PSScriptRoot\run_lsp_proxy_bits_guard.ps1" }
if (-not $IdentityGuard) { $IdentityGuard = "$PSScriptRoot\run_lsp_proxy_byte_identity_guard.ps1" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$n, [bool]$ok, [string]$d) {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

function Frame([string]$body) {
  $bb = [Text.Encoding]::UTF8.GetBytes($body)
  return [byte[]]([Text.Encoding]::ASCII.GetBytes("Content-Length: $($bb.Length)`r`n`r`n") + $bb)
}

Write-Host 'run_v1523_PROXY_child_killed -- a killed DelphiLSP child is named, and guards reap only their own' -ForegroundColor Cyan
foreach ($need in @($Exe, $BitsGuard, $IdentityGuard)) {
  if (-not (Test-Path $need)) { Write-Host "FATAL: not found -- $need" -ForegroundColor Red; Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
}
if (-not (Test-Path $Server)) {
  Write-Host "SKIP: DelphiLSP not installed at $Server" -ForegroundColor Yellow
  Write-Host 'PASS' -ForegroundColor Green
  exit 0
}

# ---- (A) ---------------------------------------------------------------------
Write-Host ''
Write-Host 'CASE A: the DelphiLSP child is killed mid-session' -ForegroundColor Cyan
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Exe
foreach ($a in @('lsp', '--proxy')) { [void]$psi.ArgumentList.Add($a) }
$psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$psi.WorkingDirectory = $env:TEMP
$p = [System.Diagnostics.Process]::Start($psi)
$outMs = New-Object System.IO.MemoryStream
$errMs = New-Object System.IO.MemoryStream
$outT = $p.StandardOutput.BaseStream.CopyToAsync($outMs)
$errT = $p.StandardError.BaseStream.CopyToAsync($errMs)
$init = Frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":null,"capabilities":{}}}'
$p.StandardInput.BaseStream.Write($init, 0, $init.Length)
$p.StandardInput.BaseStream.Flush()
$deadline = (Get-Date).AddSeconds(30); $replied = $false
while ((Get-Date) -lt $deadline -and -not $p.HasExited) {
  Start-Sleep -Milliseconds 200
  if ([Text.Encoding]::ASCII.GetString($outMs.ToArray()) -match '"id"\s*:\s*1\s*[,}]') { $replied = $true; break }
}
Check 'initialize answered through the proxy' $replied ''
$child = @(Get-CimInstance Win32_Process -Filter "Name='DelphiLSP.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.ParentProcessId -eq $p.Id })
Check 'the proxy has exactly one DelphiLSP child (positive control)' ($child.Count -eq 1) "n=$($child.Count)"
if ($child.Count -ge 1) { ([System.Diagnostics.Process]::GetProcessById([int]$child[0].ProcessId)).Kill() }
$exited = $p.WaitForExit(20000)
if (-not $exited) { try { $p.Kill($true) } catch { } }
[void]$outT.Wait(3000); [void]$errT.Wait(3000)
$err = [Text.Encoding]::UTF8.GetString($errMs.ToArray())
Check 'the proxy exits once its child is gone' $exited ''
Check 'the child''s -1 is relayed (the owner''s 4294967295)' ($exited -and $p.ExitCode -eq -1) "exit $($p.ExitCode)"
Check 'stderr names the child''s code and that it came before shutdown' `
  ($err -match 'DelphiLSP exited with code 0xFFFFFFFF before the client''s shutdown request') "stderr: $($err.Trim())"
try { $p.StandardInput.BaseStream.Close() } catch { }

# ---- (B) ---------------------------------------------------------------------
Write-Host ''
Write-Host 'CASE B: a foreign DelphiLSP survives the proxy guards' -ForegroundColor Cyan
$dpsi = New-Object System.Diagnostics.ProcessStartInfo
$dpsi.FileName = $Server
$dpsi.RedirectStandardInput = $true; $dpsi.RedirectStandardOutput = $true; $dpsi.RedirectStandardError = $true
$dpsi.UseShellExecute = $false; $dpsi.CreateNoWindow = $true
$dpsi.WorkingDirectory = $env:TEMP
foreach ($g in @($BitsGuard, $IdentityGuard)) {
  # a fresh decoy per guard, so each guard is measured on its own
  $leaf = Split-Path $g -Leaf
  $decoy = [System.Diagnostics.Process]::Start($dpsi)
  try {
    Start-Sleep -Milliseconds 1500
    Check "the decoy DelphiLSP is running before $leaf (positive control)" (-not $decoy.HasExited) "pid $($decoy.Id)"
    $o = & { $ErrorActionPreference = 'Continue'; & pwsh -NoProfile -File $g -Exe $Exe 2>&1 | Out-String }
    $code = $LASTEXITCODE
    Check "$leaf passes" ($code -eq 0 -and $o -match '(?m)^PASS\s*$') "exit $code"
    $decoy.Refresh()
    Check "the decoy survives $leaf" (-not $decoy.HasExited) $(if ($decoy.HasExited) { "exit $($decoy.ExitCode)" } else { '' })
  } finally {
    if (-not $decoy.HasExited) { try { $decoy.Kill() } catch { } }
  }
}
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
