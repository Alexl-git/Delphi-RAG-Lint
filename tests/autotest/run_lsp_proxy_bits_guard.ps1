#Requires -Version 7
# dl:serial: LSP proxy family -- spawns and reaps DelphiLSP children (see run_lsp_proxy_byte_identity_guard.ps1).
<#
  run_lsp_proxy_bits_guard.ps1 -- `drag-lint lsp --proxy --delphi-lsp-bits 32|64`
  (task C4, INBOX-ide-lsp-ram-and-shim-todo.md:99-106).

  WHAT THIS PINS
    1. --delphi-lsp-bits 16 (any value other than 32 / 64) exits 3 and names the
       flag.  This case needs no RAD Studio and always runs.
    2. With --delphi-lsp-bits 32 and no --delphi-lsp the proxy resolves
       <Studio>\bin\DelphiLSP.exe (the 32-bit server), not bin64.  POSITIVE
       CONTROL: the spawned child's image path is read while the session runs;
       the replies alone cannot tell, because the INBOX measured the 32-bit and
       64-bit capabilities as byte-identical.
    3. The `initialize` result's capabilities object is JSON-equal across: the
       proxy at 32, the proxy at 64 (the default), and a direct 32-bit
       DelphiLSP.  Non-vacuous: each side must actually carry a capabilities
       object (an empty-vs-empty comparison would pass with the feature off).

  When bin\DelphiLSP.exe is absent the guard prints SKIP after case 1 and
  exits 0 -- never a silent PASS of the Studio-dependent cases.

  RED PROOF: against the pre-change engine the --delphi-lsp-bits 32 run exits 3
  with "Unknown argument: --delphi-lsp-bits" and carries no replies.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$Studio  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0',
  [string]$Session = "$PSScriptRoot\fixtures\lspproxy\session-basic.txt"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$n, [bool]$ok, [string]$d) {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

function Reap {
  foreach ($n in @('DelphiLSP','Agent0','Agent1')) {
    foreach ($q in (Get-Process $n -ErrorAction SilentlyContinue)) { try { $q.Kill() } catch { } }
  }
}

# Plays $payload into $exe; returns stdout bytes, exit code and the image paths of
# any DelphiLSP.exe seen running while the session was in flight.
function Play {
  param([string]$exe, [string[]]$argv, [byte[]]$payload)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe
  foreach ($a in $argv) { [void]$psi.ArgumentList.Add($a) }
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.WorkingDirectory = (Split-Path $Session -Parent)
  $p = [System.Diagnostics.Process]::Start($psi)
  $outMs = New-Object System.IO.MemoryStream
  $errMs = New-Object System.IO.MemoryStream
  $outT = $p.StandardOutput.BaseStream.CopyToAsync($outMs)
  $errT = $p.StandardError.BaseStream.CopyToAsync($errMs)
  if ($p.WaitForExit(1500)) {
    [void]$outT.Wait(3000); [void]$errT.Wait(3000)
    return [pscustomobject]@{ Out = $outMs.ToArray(); Err = [Text.Encoding]::UTF8.GetString($errMs.ToArray()); Code = $p.ExitCode; Images = @() }
  }
  $p.StandardInput.BaseStream.Write($payload, 0, $payload.Length)
  $p.StandardInput.BaseStream.Flush()
  $images = @(); $last = -1; $stableAt = $null
  $deadline = (Get-Date).AddSeconds(30)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 200
    foreach ($w in @(Get-CimInstance Win32_Process -Filter "Name='DelphiLSP.exe'" -ErrorAction SilentlyContinue)) {
      if ($w.ExecutablePath -and ($images -notcontains $w.ExecutablePath)) { $images += $w.ExecutablePath }
    }
    $len = $outMs.Length
    if ($len -ne $last) { $last = $len; $stableAt = Get-Date; continue }
    if ($len -gt 0 -and $stableAt -and ((Get-Date) - $stableAt).TotalMilliseconds -ge 1500) { break }
  }
  try { $p.StandardInput.BaseStream.Close() } catch { }
  if (-not $p.WaitForExit(10000)) { $p.Kill($true) }
  [void]$outT.Wait(3000); [void]$errT.Wait(3000)
  return [pscustomobject]@{ Out = $outMs.ToArray(); Err = [Text.Encoding]::UTF8.GetString($errMs.ToArray()); Code = $p.ExitCode; Images = $images }
}

# The id:1 reply's capabilities object, re-serialised canonically ('' = absent).
function Caps([byte[]]$b) {
  $t = [Text.Encoding]::UTF8.GetString($b)
  foreach ($m in [regex]::Matches($t, '\{"jsonrpc":"2\.0","id":1,.*?\}(?=Content-Length:|\s*$)', 'Singleline')) {
    try {
      $o = $m.Value | ConvertFrom-Json
      if ($o.result -and $o.result.capabilities) { return ($o.result.capabilities | ConvertTo-Json -Compress -Depth 60) }
    } catch { }
  }
  return ''
}

Write-Host 'run_lsp_proxy_bits_guard -- --delphi-lsp-bits 32|64' -ForegroundColor Cyan
foreach ($need in @($Exe, $Session)) {
  if (-not (Test-Path $need)) { Write-Host "FATAL: not found -- $need" -ForegroundColor Red; Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
}
$payload = [IO.File]::ReadAllBytes($Session)
Reap

Write-Host ''
Write-Host 'CASE A: an unsupported width is rejected (needs no Studio)' -ForegroundColor Cyan
$bad = Play $Exe @('lsp','--proxy','--delphi-lsp-bits','16') $payload
Check '--delphi-lsp-bits 16 exits 3' ($bad.Code -eq 3) "exit $($bad.Code)"
Check 'the message says the flag takes 32 or 64' ($bad.Err -match 'delphi-lsp-bits must be 32 or 64') ("stderr: " + $bad.Err.Trim())

Write-Host ''
Write-Host 'CASE A2: a bad --merge-budget-ms is rejected, not silently defaulted (group-4 P4)' -ForegroundColor Cyan
foreach ($v in @('abc', '-5')) {
  $bb = Play $Exe @('lsp','--proxy','--merge-budget-ms',$v) $payload
  Check "--merge-budget-ms $v exits 3" ($bb.Code -eq 3) "exit $($bb.Code)"
  Check "the message names --merge-budget-ms ($v)" ($bb.Err -match 'merge-budget-ms must be') ("stderr: " + $bb.Err.Trim())
}

$srv32 = Join-Path $Studio 'bin\DelphiLSP.exe'
if (-not (Test-Path $srv32)) {
  Write-Host "SKIP: 32-bit DelphiLSP not installed at $srv32 (case A only)" -ForegroundColor Yellow
  if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
}

Write-Host ''
Write-Host 'CASE B: 32-bit forwarding spawns bin\DelphiLSP.exe' -ForegroundColor Cyan
$p32 = Play $Exe @('lsp','--proxy','--delphi-lsp-bits','32') $payload
Start-Sleep -Milliseconds 400
Check '32-bit run produced replies' ($p32.Out.Length -gt 0) "$($p32.Out.Length) bytes, exit $($p32.Code); stderr: $($p32.Err.Trim())"
Check 'the child image is bin\DelphiLSP.exe (positive control)' `
  (@($p32.Images | Where-Object { $_ -ieq $srv32 }).Count -gt 0) "seen: $($p32.Images -join '; ')"
Check 'no 64-bit server was spawned' `
  (@($p32.Images | Where-Object { $_ -match '\\bin64\\' }).Count -eq 0) ''

Write-Host ''
Write-Host 'CASE C: capabilities are JSON-equal at 32, at 64 (default) and direct' -ForegroundColor Cyan
Start-Sleep -Milliseconds 400
$p64 = Play $Exe @('lsp','--proxy') $payload
Start-Sleep -Milliseconds 400
$d32 = Play $srv32 @() $payload
$c32 = Caps $p32.Out; $c64 = Caps $p64.Out; $cd = Caps $d32.Out
Check 'proxy@32 carries a capabilities object' ($c32 -ne '') "$($c32.Length) chars"
Check 'proxy@64 carries a capabilities object' ($c64 -ne '') "$($c64.Length) chars"
Check 'direct 32-bit carries a capabilities object' ($cd -ne '') "$($cd.Length) chars"
Check 'proxy@32 == proxy@64' ($c32 -ne '' -and $c32 -ceq $c64) ''
Check 'proxy@32 == direct 32-bit' ($c32 -ne '' -and $c32 -ceq $cd) ''
Check 'the 64-bit default spawned bin64' (@($p64.Images | Where-Object { $_ -match '\\bin64\\' }).Count -gt 0) "seen: $($p64.Images -join '; ')"

Reap
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
