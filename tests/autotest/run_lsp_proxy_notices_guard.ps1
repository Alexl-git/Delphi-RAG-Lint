#Requires -Version 7
# dl:serial: LSP proxy family. Spawns and reaps LspStub children (see the sibling proxy guards).
<#
  run_lsp_proxy_notices_guard.ps1 -- lsp --proxy --merge-completion forwards the
  embedded index server's draglint/context notifications (with `notice`) and
  window/showMessage to the client, and auto re-indexes a project DB marked
  needs-re-resolve at most once per DB, never retried (direct mode already does:
  see run_lsp_context_reindex_guard.ps1; this is the proxy-mode twin).

  SAFETY: no run ever touches a real DB. The marker is the TEST seam
  DRAGLINT_LSP_TEST_MARK_INCOMPLETE (names a FIXTURE db under $WorkDir) and the
  re-index child is the seam DRAGLINT_LSP_REINDEX_EXE (a stub .cmd that records
  its arguments and exits).

  PC    no marker           -> draglint/context arrives, notice "", no run
  OK    marker + ok stub    -> 1 run (index --project A.dproj --db A.sqlite);
                               context notice "re-index in progress" then "";
                               showMessage "re-index in progress" once
  FAIL  marker + fail stub  -> 1 run (opened twice); notice names "failed" + "exit 3"

  RUN RED FIRST on the base engine (PC fails: no draglint/context reaches a
  proxied client at all). Pass -Exe of a build containing the change.
  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-proxy-notices-$PID"
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
function Write-Ascii($p, $t) { [System.IO.File]::WriteAllText($p, $t, [System.Text.Encoding]::ASCII) }
function Lines([string[]]$a) { ($a -join "`r`n") + "`r`n" }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
foreach ($d in 'A', 'lib', 'cmd', 'stub') { New-Item -ItemType Directory -Force "$WorkDir\$d" | Out-Null }
$env:DRAGLINT_CONTEXT_DEFAULTS = "$WorkDir\no-defaults.json"
foreach ($v in 'DRAGLINT_STUB_PUBLISH_FILE', 'DRAGLINT_STUB_SCRIPT', 'DRAGLINT_STUB_LOG', 'DRAGLINT_STUB_LINGER', 'DRAGLINT_MERGE_TEST_EMPTY_REPLACEMENT') {
  [Environment]::SetEnvironmentVariable($v, $null, 'Process')
}

# --- the stub DelphiLSP, built like the sibling proxy guards build it -----------
$fixtureDir = "$PSScriptRoot\fixtures\lspproxy"
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$null = cmd /c "call `"$rs`" && cd /d `"$fixtureDir`" && dcc64 -CC -E`"$WorkDir\stub`" -N0`"$WorkDir\stub`" LspStubServer.dpr" 2>&1
$stubLsp = "$WorkDir\stub\LspStubServer.exe"
Check 'SETUP: LspStubServer.exe built' (Test-Path $stubLsp)

Write-Ascii "$WorkDir\A\A.dproj" (Lines @('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">', '  <PropertyGroup>',
  "    <Config Condition=`"'`$(Config)'==''`">Debug</Config>", "    <Platform Condition=`"'`$(Platform)'==''`">Win64</Platform>",
  '  </PropertyGroup>', '</Project>'))
Write-Ascii "$WorkDir\A\uA.pas" (Lines @('unit uA;', 'interface', 'procedure OnlyInA;', 'implementation',
  'procedure OnlyInA;', 'begin', '  OnlyInA;', 'end;', 'end.'))
Write-Ascii "$WorkDir\lib\uLib.pas" (Lines @('unit uLib;', 'interface', 'procedure LibOnly;', 'implementation', 'procedure LibOnly;', 'begin', 'end;', 'end.'))
$dbA = "$WorkDir\A.sqlite"; $dbL = "$WorkDir\library-Win64.sqlite"
& $Exe index "$WorkDir\A" --db $dbA 2>&1 | Out-Null
& $Exe index "$WorkDir\lib" --db $dbL 2>&1 | Out-Null
Check 'SETUP: fixture indexes built' ((Test-Path $dbA) -and (Test-Path $dbL))
Check 'SAFETY: the marked DB is a fixture under the work dir' ($dbA.StartsWith($WorkDir, [StringComparison]::OrdinalIgnoreCase))
$calls = "$WorkDir\cmd\calls.txt"
Write-Ascii "$WorkDir\cmd\ok.cmd" (Lines @('@echo %*>>"%~dp0calls.txt"', '@ping -n 3 127.0.0.1 >nul', '@exit /b 0'))
Write-Ascii "$WorkDir\cmd\fail.cmd" (Lines @('@echo %*>>"%~dp0calls.txt"', '@echo boom: fixture failure', '@exit /b 3'))
$env:DRAGLINT_LSP_REINDEX_EXE = "$WorkDir\cmd\ok.cmd"

function Frame($obj) {
  $j = $obj | ConvertTo-Json -Depth 20 -Compress
  return [System.Text.Encoding]::UTF8.GetBytes("Content-Length: $([System.Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j")
}
function Read-Frames([string]$Out) {
  $res = @(); $i = 0
  while ($true) {
    $m = [regex]::Match($Out.Substring($i), 'Content-Length:\s*(\d+)\r\n\r\n')
    if (-not $m.Success) { break }
    $start = $i + $m.Index + $m.Length
    $len = [int]$m.Groups[1].Value
    if ($start + $len -gt $Out.Length) { break }
    try { $res += ($Out.Substring($start, $len) | ConvertFrom-Json) } catch { }
    $i = $start + $len
  }
  return $res
}
$file = "$WorkDir\A\uA.pas"; $uri = 'file:///' + ($file -replace '\\', '/')
$text = [System.IO.File]::ReadAllText($file)
# A LIVE proxied session: the proxy is kept open while the background re-index runs.
function Session([int]$Opens) {
  if (Test-Path $calls) { [System.IO.File]::Delete($calls) }
  $psi = [System.Diagnostics.ProcessStartInfo]::new($Exe)
  foreach ($a in @('lsp', '--proxy', '--merge-completion', '--db', $dbA, '--db', $dbL, '--delphi-lsp', $stubLsp)) { $psi.ArgumentList.Add($a) }
  $psi.WorkingDirectory = $WorkDir
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $ms = New-Object System.IO.MemoryStream
  $outTask = $p.StandardOutput.BaseStream.CopyToAsync($ms); $errTask = $p.StandardError.ReadToEndAsync()
  $in = $p.StandardInput.BaseStream
  function Send($o) { $b = Frame $o; $in.Write($b, 0, $b.Length); $in.Flush() }
  for ($n = 1; $n -le $Opens; $n++) {
    Send @{ jsonrpc = '2.0'; method = 'textDocument/didOpen'; params = @{ textDocument = @{ uri = $uri; languageId = 'pascal'; version = $n; text = $text } } }
  }
  Start-Sleep -Seconds 8   # one bounded wait: the stub run takes ~2 s, then the watcher re-announces
  $in.Close()
  if (-not $p.WaitForExit(30000)) { try { $p.Kill($true) } catch { }; throw 'proxy did not exit' }
  [void]$outTask.Wait(5000)
  $frames = @(Read-Frames ([System.Text.Encoding]::UTF8.GetString($ms.ToArray())))
  return @{ Err = $errTask.Result
    Calls    = @(if (Test-Path $calls) { [System.IO.File]::ReadAllLines($calls) | Where-Object { $_.Trim() -ne '' } })
    Messages = @($frames | Where-Object { $_.method -eq 'window/showMessage' } | ForEach-Object { [string]$_.params.message })
    Context  = @($frames | Where-Object { $_.method -eq 'draglint/context' -and $_.params.uri -eq $uri }) }
}

Write-Host 'PC: no marker -> context forwarded, no run' -ForegroundColor Cyan
$env:DRAGLINT_LSP_TEST_MARK_INCOMPLETE = $null
$s = Session 1
Check 'PC: a proxied client receives draglint/context for the opened file' ($s.Context.Count -ge 1) "frames=$($s.Context.Count)"
Check 'PC: its notice is empty' ($s.Context.Count -ge 1 -and [string]$s.Context[-1].params.notice -eq '')
Check 'PC: no re-index run' ($s.Calls.Count -eq 0) ($s.Calls -join ' | ')

Write-Host 'OK: marked DB -> one background run, notice, then cleared' -ForegroundColor Cyan
$env:DRAGLINT_LSP_TEST_MARK_INCOMPLETE = $dbA
$s = Session 2
Check 'OK: exactly one run although the file was opened twice' ($s.Calls.Count -eq 1) ($s.Calls -join ' | ')
Check 'OK: run is index --project A.dproj --db A.sqlite' ($s.Calls.Count -ge 1 -and $s.Calls[0] -match '^index --project "[^"]+\\A\\A\.dproj" --db "[^"]+\\A\.sqlite"$') ($s.Calls -join ' | ')
Check 'OK: client sees notice "re-index in progress" first' ($s.Context.Count -ge 1 -and [string]$s.Context[0].params.notice -match 're-index in progress') (($s.Context | ForEach-Object { $_.params.notice }) -join ' | ')
Check 'OK: client sees the notice cleared when the run finished' ($s.Context.Count -ge 2 -and [string]$s.Context[-1].params.notice -eq '') (($s.Context | ForEach-Object { $_.params.notice }) -join ' | ')
Check 'OK: showMessage "re-index in progress" exactly once' (@($s.Messages | Where-Object { $_ -match 're-index in progress' }).Count -eq 1) ($s.Messages -join ' | ')

Write-Host 'FAIL: failing run -> notice with reason, never retried' -ForegroundColor Cyan
$env:DRAGLINT_LSP_REINDEX_EXE = "$WorkDir\cmd\fail.cmd"
$s = Session 2
Check 'FAIL: exactly one run for two opens' ($s.Calls.Count -eq 1) ($s.Calls -join ' | ')
Check 'FAIL: context notice names the failure and exit 3' ($s.Context.Count -ge 1 -and [string]$s.Context[-1].params.notice -match 're-index of A\.sqlite failed \(exit 3') (($s.Context | ForEach-Object { $_.params.notice }) -join ' | ')

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  $env:DRAGLINT_CONTEXT_DEFAULTS = $null; $env:DRAGLINT_LSP_TEST_MARK_INCOMPLETE = $null; $env:DRAGLINT_LSP_REINDEX_EXE = $null
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
