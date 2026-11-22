#Requires -Version 7
# dl:serial: LSP proxy family. Spawns and reaps LspStub / DelphiLSP children.
<#
  run_v1523_PROXY_shutdown.ps1 -- PROXY-AV (1.52.3): `lsp --proxy` exits 0 after a
  clean LSP shutdown even when DelphiLSP itself dies at exit.

  ROOT CAUSE (lane LSP-PROXY, 2026-11-20). The "drag-lint AV 0xC0000005 at
  shutdown" was never drag-lint's: RunLspProxy returns the CHILD's exit code, and
  DelphiLSP.exe (Studio 37.0, bin64) itself exits 0xC0000005 -- or 1 -- in roughly
  1 of 3 sessions after a correct shutdown/exit sequence, with or without a
  .delphilsp.json config. Measured on the bare DelphiLSP with no proxy in front;
  cdb attached to the proxy saw no access violation in drag-lint.exe.

  The LSP contract is the proxy's to keep: after `shutdown` then `exit` the server
  exits 0. So once the client's shutdown request has passed through, a non-zero
  child code is reported on stderr and the proxy exits 0. Before a shutdown the
  child's code is still relayed (a DelphiLSP crash mid-session stays visible).

  Checks (the stub echoes stdin and exits 42 -- the stand-in for DelphiLSP's crash):
    (a) plain relay, shutdown + exit sent: exit 0, stderr names the child's 42;
    (b) same with --merge-hover (the interceptor path): exit 0;
    (c) positive control: no shutdown request -> the stub's 42 is relayed;
    (d) negative control: "shutdown" only INSIDE a didOpen text -> still 42;
    (e) bytes: the client still receives every frame it sent (stub echo) -- the
        observation is read-only;
    (f) -RealRounds N (default 10): the no-config session in front of the real
        DelphiLSP exits 0 every round. Skipped (not failed) without Studio.

  -Exe defaults to dll-win64; a lane passes its own engine. Run from a NEUTRAL CWD.
#>
[CmdletBinding()]
param(
  [string]$Exe        = '',
  [string]$WorkDir    = "$env:TEMP\draglint_v1523_proxy_shutdown_$PID",
  [int]   $RealRounds = 10
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
foreach ($v in @('DRAGLINT_STUB_PUBLISH_FILE', 'DRAGLINT_STUB_SCRIPT', 'DRAGLINT_STUB_LOG', 'DRAGLINT_STUB_LINGER')) {
  [Environment]::SetEnvironmentVariable($v, $null, 'Process')
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

function Invoke-Raw {
  param([string]$exe, [string[]]$argv, [byte[]]$c1)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe
  foreach ($a in $argv) { [void]$psi.ArgumentList.Add($a) }
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.WorkingDirectory = $WorkDir
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
  $done = $p.WaitForExit(20000)
  if (-not $done) { try { $p.Kill($true) } catch { } }
  [void]$outT.Wait(5000); [void]$errT.Wait(5000)
  $code = if ($done) { $p.ExitCode } else { -999 }
  return [pscustomobject]@{ Out = $outMs.ToArray(); Err = $errMs.ToArray(); Code = $code }
}
function Ascii([byte[]]$b) { if (-not $b) { return '' } [System.Text.Encoding]::ASCII.GetString($b) }
function Frame([string]$body) {
  $bb = [System.Text.Encoding]::UTF8.GetBytes($body)
  return [byte[]]([System.Text.Encoding]::ASCII.GetBytes("Content-Length: $($bb.Length)`r`n`r`n") + $bb)
}

Write-Host ''
Write-Host 'run_v1523_PROXY_shutdown -- proxy exits 0 after a clean shutdown (PROXY-AV)' -ForegroundColor Cyan

$fixtureDir = "$PSScriptRoot\fixtures\lspproxy"
$outDir     = Join-Path $WorkDir 'stub'
New-Item -ItemType Directory $outDir | Out-Null
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$null = & { $ErrorActionPreference = 'Continue'; cmd /c "call `"$rs`" && cd /d `"$fixtureDir`" && dcc64 -CC -E`"$outDir`" -N0`"$outDir`" LspStubServer.dpr" 2>&1 | ForEach-Object { "$_" } }
$stub = "$outDir\LspStubServer.exe"
Check 'LspStubServer.exe built' (Test-Path $stub) $stub
if (-not (Test-Path $stub)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

$init     = Frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":null,"capabilities":{}}}'
$shutdown = Frame '{"jsonrpc":"2.0","id":2,"method":"shutdown","params":null}'
$exitN    = Frame '{"jsonrpc":"2.0","method":"exit","params":null}'
$decoy    = Frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///c:/x/U.pas","languageId":"pascal","version":1,"text":"{\"method\":\"shutdown\"} shutdown"}}}'

# (a) plain relay
$clean = [byte[]]($init + $shutdown + $exitN)
$a = Invoke-Raw $Exe @('lsp', '--proxy', '--delphi-lsp', $stub) $clean
Check '(a) plain relay: exit 0 after shutdown + exit' ($a.Code -eq 0) "code=$($a.Code)"
Check '(a) stderr names the child''s exit code' ((Ascii $a.Err) -match 'exited with code 0x0000002A after the client''s shutdown') ((Ascii $a.Err).Trim())
# (e) the echo stub returns every client byte: the observation must not alter the stream
Check '(e) every client frame reaches the child unchanged' ((Ascii $a.Out).Contains((Ascii $clean))) ''

# (b) interceptor path
$b = Invoke-Raw $Exe @('lsp', '--proxy', '--merge-hover', '--merge-budget-ms', '0', '--delphi-lsp', $stub) $clean
Check '(b) --merge-hover: exit 0 after shutdown + exit' ($b.Code -eq 0) "code=$($b.Code)"

# (c) positive control: the child's code is still relayed without a shutdown
$c = Invoke-Raw $Exe @('lsp', '--proxy', '--delphi-lsp', $stub) ([byte[]]($init + $exitN))
Check '(c) control: no shutdown -> the child''s 42 is relayed' ($c.Code -eq 42) "code=$($c.Code)"

# (d) negative control: "shutdown" inside a document text is not a shutdown request
$d = Invoke-Raw $Exe @('lsp', '--proxy', '--delphi-lsp', $stub) ([byte[]]($init + $decoy + $exitN))
Check '(d) control: "shutdown" in a didOpen text -> still 42' ($d.Code -eq 42) "code=$($d.Code)"

# (f) the real DelphiLSP, no config, N rounds
$dlsp = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin64\DelphiLSP.exe'
if ($RealRounds -le 0) { Write-Host '  [SKIP] (f) -RealRounds 0' -ForegroundColor Yellow }
elseif (-not (Test-Path $dlsp)) { Write-Host "  [SKIP] (f) no $dlsp" -ForegroundColor Yellow }
else {
  $unit = Join-Path $WorkDir 'U.pas'
  [IO.File]::WriteAllText($unit, "unit U;`r`ninterface`r`nprocedure P;`r`nimplementation`r`nprocedure P;`r`nbegin`r`nend;`r`nend.`r`n")
  $uri  = 'file:///' + ($unit -replace '\\', '/')
  $open = Frame ('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"' + $uri + '","languageId":"pascal","version":1,"text":' + ([IO.File]::ReadAllText($unit) | ConvertTo-Json) + '}}}')
  $hover = Frame ('{"jsonrpc":"2.0","id":3,"method":"textDocument/hover","params":{"textDocument":{"uri":"' + $uri + '"},"position":{"line":5,"character":1}}}')
  $codes = @()
  for ($i = 1; $i -le $RealRounds; $i++) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    foreach ($x in @('lsp', '--proxy')) { [void]$psi.ArgumentList.Add($x) }
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $WorkDir
    $p = [System.Diagnostics.Process]::Start($psi)
    $outT = $p.StandardOutput.BaseStream.CopyToAsync([System.IO.Stream]::Null)
    $errT = $p.StandardError.BaseStream.CopyToAsync([System.IO.Stream]::Null)
    $sin = $p.StandardInput.BaseStream
    foreach ($f in @($init, (Frame '{"jsonrpc":"2.0","method":"initialized","params":{}}'), $open)) { $sin.Write($f, 0, $f.Length); $sin.Flush() }
    Start-Sleep -Milliseconds 3000
    foreach ($f in @($hover, $shutdown)) { $sin.Write($f, 0, $f.Length); $sin.Flush() }
    Start-Sleep -Milliseconds 1000
    $sin.Write($exitN, 0, $exitN.Length); $sin.Flush(); $sin.Close()
    $done = $p.WaitForExit(30000)
    if (-not $done) { try { $p.Kill($true) } catch { } }
    [void]$outT.Wait(5000); [void]$errT.Wait(5000)
    $codes += if ($done) { $p.ExitCode } else { -999 }
  }
  $bad = @($codes | Where-Object { $_ -ne 0 })
  Check "(f) real DelphiLSP, no config: exit 0 in $RealRounds of $RealRounds rounds" ($bad.Count -eq 0) ("codes=" + ($codes -join ','))
}

Write-Host ''
if ($script:Failed) { Write-Host 'run_v1523_PROXY_shutdown: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_v1523_PROXY_shutdown: PASS' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
