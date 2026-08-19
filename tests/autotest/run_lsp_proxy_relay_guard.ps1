<#
  run_lsp_proxy_relay_guard.ps1 -- `drag-lint lsp --proxy` must be a
  TRANSPARENT relay: the client sees exactly the bytes it would have seen
  talking to the language server directly, in both directions.

  WHAT THIS PINS (spec 2026-08-18-lsp-merge-proxy-design.md, criteria 1, 3, 7):

    1. every byte forwarded unmodified, both directions
    3. an unspawnable child is a non-zero exit with a diagnostic on stderr,
       NOT a server that accepts requests it cannot answer
    7. the child is resolved to bin64\DelphiLSP.exe when not overridden

  WHY IT COMPARES AGAINST A DIRECT RUN RATHER THAN A LITERAL. The assertion
  that matters is "indistinguishable from talking to the server itself", so the
  expected value is produced by talking to the server itself. A hardcoded
  expected string would drift the moment the stub changed and would quietly
  become an assertion about the stub instead of about the relay.

  WHY A SPLIT WRITE. A relay that reframes -- buffers until it thinks it has a
  whole message, then re-emits it -- passes a single-write test. The payload is
  therefore delivered in two writes with a pause between them, and the split
  falls INSIDE the second message's Content-Length header, which is the point a
  naive reader is most likely to mishandle. Task 4 replaces the raw pump with a
  framing reader; this guard is what proves that change kept byte-identity.

  RED PROOF (recorded 2026-08-18): run against the pre-change
  src\cli\Win64\Debug\drag-lint.exe, every relay case fails -- the binary
  rejects --proxy during argument parsing, so nothing is spawned and stdout
  carries no stub bytes at all.
#>

[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_lspproxy_relay"
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$n, [bool]$ok, [string]$d) {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

function Hex([byte[]]$b, [int]$max = 60) {
  if ($null -eq $b) { return '<null>' }
  $take = [Math]::Min($max, $b.Length)
  if ($take -eq 0) { return '<empty>' }
  return (($b[0..($take - 1)] | ForEach-Object { $_.ToString('x2') }) -join '') +
         $(if ($b.Length -gt $take) { "... ($($b.Length) bytes)" } else { " ($($b.Length) bytes)" })
}

# Runs $exe with $argv, writing $c1 then (after a pause) $c2 to its stdin, and
# returns the raw stdout/stderr bytes plus the exit code. Reading both streams
# asynchronously is not optional: a child that fills the 4 KB stdout pipe while
# we are blocked writing stdin deadlocks, and the deadlock looks exactly like a
# relay that stopped forwarding.
function Invoke-Raw {
  param([string]$exe, [string[]]$argv, [byte[]]$c1, [byte[]]$c2, [int]$pauseMs = 250)

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
    if ($c2 -and $c2.Length) {
      Start-Sleep -Milliseconds $pauseMs
      $sin.Write($c2, 0, $c2.Length); $sin.Flush()
    }
    $sin.Close()
  } catch {
    # A child that died before we finished writing (the spawn-failure case) is a
    # broken pipe here, not a test error -- the exit code below is the verdict.
  }

  if (-not $p.WaitForExit(20000)) { $p.Kill($true); throw "timed out: $exe" }
  [void]$outT.Wait(5000)
  [void]$errT.Wait(5000)

  return [pscustomobject]@{
    Out  = $outMs.ToArray()
    Err  = [System.Text.Encoding]::ASCII.GetString($errMs.ToArray())
    Code = $p.ExitCode
  }
}

function BytesEqual([byte[]]$a, [byte[]]$b) {
  if ($a.Length -ne $b.Length) { return $false }
  for ($i = 0; $i -lt $a.Length; $i++) { if ($a[$i] -ne $b[$i]) { return $false } }
  return $true
}

Write-Host 'run_lsp_proxy_relay_guard -- transparent relay in front of DelphiLSP' -ForegroundColor Cyan

if (-not (Test-Path $Exe)) {
  Write-Host "FATAL: engine not found at $Exe -- build it first" -ForegroundColor Red
  Write-Host 'FAIL' -ForegroundColor Red
  exit 1
}

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

# ---- build the stub server -------------------------------------------------
# A bare .dpr cannot be built by msbuild, so use dcc64 from rsvars -- the same
# recipe run_hover_callers_scope_guard.ps1 uses for its harness.
$rsvars     = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$fixtureDir = "$PSScriptRoot\fixtures\lspproxy"
$outDir     = "$fixtureDir\Win64\Debug"
New-Item -ItemType Directory -Force $outDir | Out-Null

$batPath = "$WorkDir\build_stub.bat"
$logPath = "$WorkDir\build_stub.log"
$batBody = (@(
  '@echo off'
  "call `"$rsvars`""
  "cd /d `"$fixtureDir`""
  "dcc64 -CC -E`"$outDir`" -N0`"$outDir`" LspStubServer.dpr"
  'echo BUILD_EXITCODE=%ERRORLEVEL%'
) -join "`r`n")
[System.IO.File]::WriteAllText($batPath, $batBody, [System.Text.Encoding]::ASCII)

$null = Start-Process cmd.exe -ArgumentList "/c", "`"$batPath`"" `
          -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" `
          -NoNewWindow -Wait -PassThru
$log     = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
$buildOk = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:')
Check 'LspStubServer.dpr builds (Win64)' $buildOk `
  (($log -split "`r?`n" | Select-Object -Last 4) -join ' | ')

$stub = "$outDir\LspStubServer.exe"
if (-not $buildOk -or -not (Test-Path $stub)) {
  Write-Host "FATAL: stub exe not found at $stub -- see $logPath" -ForegroundColor Red
  Write-Host 'FAIL' -ForegroundColor Red
  exit 1
}

# ---- the payload -----------------------------------------------------------
# Two properly framed LSP messages, split mid-header of the second one.
$body1 = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
$body2 = '{"jsonrpc":"2.0","id":2,"method":"shutdown","params":null}'
$msg1  = "Content-Length: $($body1.Length)`r`n`r`n$body1"
$msg2  = "Content-Length: $($body2.Length)`r`n`r`n$body2"
$all   = [System.Text.Encoding]::ASCII.GetBytes($msg1 + $msg2)

$splitAt = $msg1.Length + 8      # inside "Content-Length:" of the second message
$chunk1  = $all[0..($splitAt - 1)]
$chunk2  = $all[$splitAt..($all.Length - 1)]

Write-Host ''
Write-Host 'CASE A: byte-identity against a direct connection' -ForegroundColor Cyan

$direct = Invoke-Raw $stub @()                               $chunk1 $chunk2
$proxy  = Invoke-Raw $Exe  @('lsp','--proxy','--delphi-lsp',$stub) $chunk1 $chunk2

Check 'direct run produced output' ($direct.Out.Length -gt 0) (Hex $direct.Out)
Check 'proxy  run produced output' ($proxy.Out.Length -gt 0) (Hex $proxy.Out)
Check 'stdout is byte-identical to a direct connection' `
  (BytesEqual $direct.Out $proxy.Out) `
  ("direct=$(Hex $direct.Out 24) proxy=$(Hex $proxy.Out 24)")

Write-Host ''
Write-Host 'CASE B: what the identity actually contains' -ForegroundColor Cyan
# Byte-identity with a direct run is necessary but not sufficient: two EMPTY
# streams are also identical. Name the bytes that must be in there.
$proxyText = [System.Text.Encoding]::ASCII.GetString($proxy.Out)
Check 'the child-to-client direction carried the preamble' `
  ($proxyText.StartsWith('STUB-PREAMBLE-BEGIN')) "got: $($proxyText.Substring(0, [Math]::Min(40, $proxyText.Length)))"
Check 'the client-to-child direction carried message 1' `
  ($proxyText.Contains($msg1)) 'echoed body of the first framed message'
Check 'the client-to-child direction carried message 2 across the split' `
  ($proxyText.Contains($msg2)) 'the message whose header was cut in two'
Check 'the stream ended with the trailer' `
  ($proxyText.EndsWith('STUB-TRAILER-END')) 'nothing was dropped at EOF'

Write-Host ''
Write-Host 'CASE C: stderr and exit code come from the child' -ForegroundColor Cyan
Check 'the child stderr line reached the client' `
  ($proxy.Err -match 'STUB-STDERR-LINE') "got: $($proxy.Err.Trim())"
Check 'the child exit code is propagated (42)' `
  ($proxy.Code -eq 42) "got: $($proxy.Code)"

Write-Host ''
Write-Host 'CASE D: criterion 3 -- an unspawnable child FAILS, it does not idle' -ForegroundColor Cyan
$missing = "$WorkDir\no-such-lsp.exe"
$dead    = Invoke-Raw $Exe @('lsp','--proxy','--delphi-lsp',$missing) $chunk1 $null 0
Check 'exit code is non-zero' ($dead.Code -ne 0) "got: $($dead.Code)"
Check 'a diagnostic naming the path went to stderr' `
  ($dead.Err -match [regex]::Escape('no-such-lsp.exe')) "got: $($dead.Err.Trim())"
Check 'nothing was written to stdout' ($dead.Out.Length -eq 0) (Hex $dead.Out)

Write-Host ''
Write-Host 'CASE E: criterion 7 -- the default child is bin64\DelphiLSP.exe' -ForegroundColor Cyan
# Resolution is asserted through the failure message rather than by spawning the
# real server: this must hold on a machine where Studio is absent, and spawning
# DelphiLSP for real would make the guard depend on the IDE it exists to protect.
$studio  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin64\DelphiLSP.exe'
if (Test-Path $studio) {
  Check 'bin64\DelphiLSP.exe is present on this machine' $true $studio
} else {
  $noStudio = Invoke-Raw $Exe @('lsp','--proxy') $chunk1 $null 0
  Check 'without Studio, the relay reports bin64\DelphiLSP.exe and exits non-zero' `
    (($noStudio.Code -ne 0) -and ($noStudio.Err -match 'bin64')) "got: $($noStudio.Err.Trim())"
}

Write-Host ''
Write-Host 'CASE F: a message far larger than one pipe read' -ForegroundColor Cyan
# Task 4 replaced the raw pump with a framing reader that must REASSEMBLE a
# message spanning many reads before forwarding it. A 300 KB body crosses the
# 64 KB pump buffer several times and forces the accumulator to grow, which is
# the path a single small message never touches. The split lands mid-BODY here,
# not mid-header, so both halves of the reassembly are exercised.
$bigBody  = '{"jsonrpc":"2.0","id":9,"method":"big","params":{"pad":"' + ('x' * 300000) + '"}}'
$bigMsg   = "Content-Length: $($bigBody.Length)`r`n`r`n$bigBody"
$bigBytes = [System.Text.Encoding]::ASCII.GetBytes($bigMsg)
$bigAt    = 100000
$bigC1    = $bigBytes[0..($bigAt - 1)]
$bigC2    = $bigBytes[$bigAt..($bigBytes.Length - 1)]

$bigDirect = Invoke-Raw $stub @()                                  $bigC1 $bigC2
$bigProxy  = Invoke-Raw $Exe  @('lsp','--proxy','--delphi-lsp',$stub) $bigC1 $bigC2
Check 'the large message survived the relay intact' `
  (BytesEqual $bigDirect.Out $bigProxy.Out) `
  ("direct=$($bigDirect.Out.Length)b proxy=$($bigProxy.Out.Length)b")
Check 'nothing was truncated' `
  ($bigProxy.Out.Length -eq ($bigDirect.Out.Length)) "expected $($bigDirect.Out.Length) bytes"
Check 'the whole 300 KB body came back' `
  ([System.Text.Encoding]::ASCII.GetString($bigProxy.Out).Contains($bigBody)) 'body echoed in full'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
