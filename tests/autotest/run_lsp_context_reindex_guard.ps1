#Requires -Version 7
<#
  run_lsp_context_reindex_guard.ps1 -- LSP-1 CORE, owner ruling 2026-10-28: when
  the LSP opens a project DB that needs re-resolve it starts a SEPARATE engine
  process (`index --project <dproj> --db <db>`) in the background, at most one
  run per DB, never retried after a failure; while it runs answers continue and
  "re-index in progress" shows in the hover footer, in draglint/context's notice
  and once via showMessage; when it exits the notice clears and diagnostics are
  republished.

  SAFETY: no run ever touches a real DB. The marker is the TEST seam
  DRAGLINT_LSP_TEST_MARK_INCOMPLETE (names a FIXTURE db, asserted under
  $WorkDir), and the child is the seam DRAGLINT_LSP_REINDEX_EXE (a stub .cmd
  that records its arguments and exits).

  PC    no marker            -> no run, no re-index notice
  OK    marker + ok stub     -> 1 run with --project A.dproj --db A.sqlite; notice once;
                                footer "in progress" then gone; context notice cleared;
                                diagnostics republished
  FAIL  marker + fail stub   -> 1 run only (3 hovers); notice names "failed" + "exit 3"

  RUN RED FIRST on the deployed engine: OK and FAIL fail; PC passes.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-ctx-reidx-$PID"
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
foreach ($d in 'A', 'lib', 'stub') { New-Item -ItemType Directory -Force "$WorkDir\$d" | Out-Null }
$env:DRAGLINT_CONTEXT_DEFAULTS = "$WorkDir\no-defaults.json"

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
$calls = "$WorkDir\stub\calls.txt"
Write-Ascii "$WorkDir\stub\ok.cmd" (Lines @('@echo %*>>"%~dp0calls.txt"', '@ping -n 3 127.0.0.1 >nul', '@exit /b 0'))
Write-Ascii "$WorkDir\stub\fail.cmd" (Lines @('@echo %*>>"%~dp0calls.txt"', '@echo boom: fixture failure', '@exit /b 3'))
$env:DRAGLINT_LSP_REINDEX_EXE = "$WorkDir\stub\ok.cmd"

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
    $res += ($Out.Substring($start, $len) | ConvertFrom-Json)
    $i = $start + $len
  }
  return $res
}
$file = "$WorkDir\A\uA.pas"; $uri = 'file:///' + ($file -replace '\\', '/')
function Hover($id) { @{ jsonrpc = '2.0'; id = $id; method = 'textDocument/hover'; params = @{ textDocument = @{ uri = $uri }; position = @{ line = 6; character = 4 } } } }
# A LIVE session: frames are written with pauses, so the background run can finish while the server waits.
function Session() {
  if (Test-Path $calls) { [System.IO.File]::Delete($calls) }
  $psi = [System.Diagnostics.ProcessStartInfo]::new($Exe)
  foreach ($a in @('lsp', '--db', $dbA, '--db', $dbL)) { $psi.ArgumentList.Add($a) }
  $psi.WorkingDirectory = $WorkDir
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $outTask = $p.StandardOutput.ReadToEndAsync(); $errTask = $p.StandardError.ReadToEndAsync()
  $in = $p.StandardInput.BaseStream
  function Send($o) { $b = Frame $o; $in.Write($b, 0, $b.Length); $in.Flush() }
  Send @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ processId = $null; rootUri = $null; capabilities = @{} } }
  Send @{ jsonrpc = '2.0'; method = 'initialized'; params = @{} }
  Send @{ jsonrpc = '2.0'; method = 'textDocument/didOpen'; params = @{ textDocument = @{ uri = $uri; languageId = 'pascal'; version = 1; text = [System.IO.File]::ReadAllText($file) } } }
  Send (Hover 10)
  Send (Hover 11)
  Start-Sleep -Seconds 8
  Send (Hover 12)
  Start-Sleep -Milliseconds 500
  Send @{ jsonrpc = '2.0'; id = 99; method = 'shutdown'; params = @{} }
  Send @{ jsonrpc = '2.0'; method = 'exit'; params = @{} }
  $in.Close()
  if (-not $p.WaitForExit(30000)) { $p.Kill(); throw 'lsp did not exit' }
  $frames = @(Read-Frames $outTask.Result)
  $hov = @{}
  foreach ($id in 10, 11, 12) {
    $r = @($frames | Where-Object { $_.id -eq $id })
    $hov[$id] = if ($r.Count -gt 0 -and $null -ne $r[0].result) { [string]$r[0].result.contents.value } else { '' }
  }
  return @{ Hover = $hov; Err = $errTask.Result
    Calls    = @(if (Test-Path $calls) { [System.IO.File]::ReadAllLines($calls) | Where-Object { $_.Trim() -ne '' } })
    Messages = @($frames | Where-Object { $_.method -eq 'window/showMessage' } | ForEach-Object { [string]$_.params.message })
    Context  = @($frames | Where-Object { $_.method -eq 'draglint/context' -and $_.params.uri -eq $uri })
    Diags    = @($frames | Where-Object { $_.method -eq 'textDocument/publishDiagnostics' -and $_.params.uri -eq $uri }) }
}

Write-Host 'PC: no marker -> no run' -ForegroundColor Cyan
$env:DRAGLINT_LSP_TEST_MARK_INCOMPLETE = $null
$s = Session
Check 'PC: hover answers' ($s.Hover[10] -match 'OnlyInA')
Check 'PC: no re-index run' ($s.Calls.Count -eq 0) ($s.Calls -join ' | ')
Check 'PC: no re-index notice' (@($s.Messages | Where-Object { $_ -match 're-index' }).Count -eq 0) ($s.Messages -join ' | ')

Write-Host 'OK: marked DB -> one background run, notice, then cleared' -ForegroundColor Cyan
$env:DRAGLINT_LSP_TEST_MARK_INCOMPLETE = $dbA
$s = Session
Check 'OK: exactly one run' ($s.Calls.Count -eq 1) ($s.Calls -join ' | ')
Check 'OK: run is index --project A.dproj --db A.sqlite' ($s.Calls.Count -ge 1 -and $s.Calls[0] -match '^index --project "[^"]+\\A\\A\.dproj" --db "[^"]+\\A\.sqlite"$') ($s.Calls -join ' | ')
Check 'OK: showMessage "re-index in progress" exactly once' (@($s.Messages | Where-Object { $_ -match 're-index in progress' }).Count -eq 1) ($s.Messages -join ' | ')
Check 'OK: answers continue while it runs' ($s.Hover[10] -match 'OnlyInA')
Check 'OK: footer says in progress while it runs' ($s.Hover[10] -match 're-index in progress')
Check 'OK: footer clean after it finished' ($s.Hover[12] -match 'OnlyInA' -and $s.Hover[12] -notmatch 're-index')
Check 'OK: draglint/context notice went from in-progress to ""' ($s.Context.Count -ge 2 -and [string]$s.Context[0].params.notice -match 're-index in progress' -and
  [string]$s.Context[-1].params.notice -eq '') (($s.Context | ForEach-Object { $_.params.notice }) -join ' | ')
Check 'OK: diagnostics republished after the run' ($s.Diags.Count -ge 2) "publishes=$($s.Diags.Count)"

Write-Host 'FAIL: failing run -> notice with reason, never retried' -ForegroundColor Cyan
$env:DRAGLINT_LSP_REINDEX_EXE = "$WorkDir\stub\fail.cmd"
$s = Session
Check 'FAIL: exactly one run for three hovers' ($s.Calls.Count -eq 1) ($s.Calls -join ' | ')
Check 'FAIL: showMessage names the failure and exit 3' (@($s.Messages | Where-Object { $_ -match 're-index of A\.sqlite failed \(exit 3' }).Count -eq 1) ($s.Messages -join ' | ')
Check 'FAIL: footer carries the failure' ($s.Hover[12] -match 'failed')
Check 'FAIL: answers continue' ($s.Hover[12] -match 'OnlyInA')

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  $env:DRAGLINT_CONTEXT_DEFAULTS = $null; $env:DRAGLINT_LSP_TEST_MARK_INCOMPLETE = $null; $env:DRAGLINT_LSP_REINDEX_EXE = $null
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
