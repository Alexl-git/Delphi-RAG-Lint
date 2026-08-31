# dl:serial: LSP proxy family. Spawns and reaps LspStub children; the sibling
#   proxy guards were observed interfering with each other even when strictly
#   serialised (root cause fixed in 41b0004), so this one joins the quarantine
#   rather than discovering the same class under concurrency.
<#
  run_lsp_proxy_trace_guard.ps1 -- `lsp --proxy --trace <file>` must record the
  session WITHOUT altering it.

  WHY THIS EXISTS. Phase 1b of the merge-proxy plan registers this relay as the
  IDE's Pascal language server. That is the step where a drag-lint bug stops
  costing drag-lint features and starts costing all of Code Insight, repaired
  through the very dialogs that are misbehaving -- so the session has to produce
  EVIDENCE, not anecdotes. Several unknowns can only be settled from inside the
  stream: what the IDE actually sends as initializationOptions, how often it
  cancels, whether it restarts the server on project activation.

  THE ASSERTION THAT MATTERS IS THE THIRD ONE. A trace that captured everything
  but perturbed a byte would be worse than none, because it would be armed
  exactly when the relay is under a live IDE. So the guard runs the SAME input
  through the proxy twice -- once with --trace, once without -- and requires the
  relayed bytes to be identical. Without that comparison this file would pass
  while the tracer corrupted the session it was recording.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_lspproxy_trace"
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Invoke-Raw {
  param([string]$exe, [string[]]$argv, [byte[]]$c1)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName               = $exe
  foreach ($a in $argv) { [void]$psi.ArgumentList.Add($a) }
  $psi.RedirectStandardInput  = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute        = $false
  $psi.CreateNoWindow         = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $outMs = New-Object System.IO.MemoryStream
  $errMs = New-Object System.IO.MemoryStream
  $outT  = $p.StandardOutput.BaseStream.CopyToAsync($outMs)
  $errT  = $p.StandardError.BaseStream.CopyToAsync($errMs)
  try {
    $sin = $p.StandardInput.BaseStream
    if ($c1 -and $c1.Length) { $sin.Write($c1, 0, $c1.Length); $sin.Flush() }
    $sin.Close()
  } catch { }
  [void]$p.WaitForExit(20000)
  [void]$outT.Wait(5000); [void]$errT.Wait(5000)
  return [pscustomobject]@{ Out = $outMs.ToArray(); Err = $errMs.ToArray() }
}
function Hex([byte[]]$b, [int]$n = 24) {
  if (-not $b -or $b.Length -eq 0) { return '(empty)' }
  ($b[0..([Math]::Min($n, $b.Length) - 1)] | ForEach-Object { $_.ToString('x2') }) -join ''
}

Write-Host ''
Write-Host 'run_lsp_proxy_trace_guard -- record the session, do not alter it' -ForegroundColor Cyan

# --- the stub server, built the same way the sibling guards build it --------
$fixtureDir = "$PSScriptRoot\fixtures\lspproxy"
$outDir     = Join-Path $WorkDir 'stub'
New-Item -ItemType Directory $outDir | Out-Null
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$null = cmd /c "call `"$rs`" && cd /d `"$fixtureDir`" && dcc64 -CC -E`"$outDir`" -N0`"$outDir`" LspStubServer.dpr" 2>&1
$stub = "$outDir\LspStubServer.exe"
Check 'LspStubServer.exe built' (Test-Path $stub) $stub
if (-not (Test-Path $stub)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

# One well-formed LSP frame. The stub answers it, so both directions carry a
# complete message and the trace has something to record in each.
$body  = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
$frame = "Content-Length: $($body.Length)`r`n`r`n$body"
$bytes = [System.Text.Encoding]::ASCII.GetBytes($frame)

$trace = Join-Path $WorkDir 'session.trace'

$plain  = Invoke-Raw $Exe @('lsp','--proxy','--delphi-lsp',$stub) $bytes
$traced = Invoke-Raw $Exe @('lsp','--proxy','--delphi-lsp',$stub,'--trace',$trace) $bytes

Write-Host ''
Write-Host 'THE TRACE' -ForegroundColor Cyan
Check 'a trace file is written' (Test-Path $trace) $trace
$txt = if (Test-Path $trace) { Get-Content $trace -Raw } else { '' }
Check 'it is not empty' ($txt.Length -gt 0) ("$($txt.Length) char(s)")
Check 'it records the CLIENT -> SERVER direction' ($txt -match 'C>S') ''
Check 'it records the SERVER -> CLIENT direction' ($txt -match 'S>C') `
  'both pumps must be traced -- one of them runs on the main thread, the other on a pump thread'
Check 'it contains the relayed payload verbatim' ($txt -match 'initialize') ''

Write-Host ''
Write-Host 'AND IT DOES NOT PERTURB THE RELAY -- the assertion that matters' -ForegroundColor Cyan
Check 'the traced run produced output at all' ($traced.Out.Length -gt 0) (Hex $traced.Out)
Check 'tracing OFF and ON relay identical bytes' `
  ($null -eq (Compare-Object $plain.Out $traced.Out -SyncWindow 0)) `
  ("off=$(Hex $plain.Out) on=$(Hex $traced.Out)")

Write-Host ''
Write-Host 'OFF BY DEFAULT' -ForegroundColor Cyan
$stray = Get-ChildItem $WorkDir -Filter '*.trace' -File | Where-Object { $_.FullName -ne $trace }
Check 'no trace file appears without --trace' ($stray.Count -eq 0) `
  'a diagnostic that writes to disk unasked is a surprise in a live IDE session'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
