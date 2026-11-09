#Requires -Version 7
<#
  run_mcp_closed_pipe_guard.ps1 -- INBOX-139 #5 second half (fixed in 1.40, 4caf2b937; no guard
  until 148 LS): when the MCP client goes away, `serve` must not die raising out of Run from its
  own error handler (SendRaw / Flush on a closed stdout). It answers into the void, sees stdin
  end and exits on its own.
    A  POSITIVE CONTROL: stdout read -> initialize and tools/list are answered (2 replies).
    B  stdout CLOSED by the client before any reply, then requests + stdin EOF -> the server
       exits by itself within 30 s, with exit 0 (not 3, the closed-pipe FATAL), and stderr
       carries no "FATAL".
  Run from any CWD, pwsh 7. -Exe defaults to the repo build.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-mcp-pipe-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
. (Join-Path $PSScriptRoot 'lsp_stdio_helpers.ps1')
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory "$WorkDir\src" -Force | Out-Null
WriteAnsi "$WorkDir\src\uA.pas" "unit uA;`r`n`r`ninterface`r`n`r`nprocedure DoA;`r`n`r`nimplementation`r`n`r`nprocedure DoA;`r`nbegin`r`nend;`r`n`r`nend.`r`n"
$db = "$WorkDir\a.sqlite"
& $Exe index "$WorkDir\src" --db $db 2>&1 | Out-Null

$reqs = @(
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"guard","version":"1"}}}',
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}',
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"find_symbol","arguments":{"name":"DoA"}}}',
  '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"no_such_tool","arguments":{}}}'
)
function Start-Serve {
  $psi = [Diagnostics.ProcessStartInfo]::new($Exe)
  foreach ($a in @('serve', '--db', $db)) { $psi.ArgumentList.Add($a) }
  $psi.WorkingDirectory = $WorkDir; $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  return [Diagnostics.Process]::Start($psi)
}

Write-Host ''
Write-Host 'run_mcp_closed_pipe_guard -- serve survives a client that closed stdout' -ForegroundColor Cyan
$p = Start-Serve
$errA = $p.StandardError.ReadToEndAsync(); $outA = $p.StandardOutput.ReadToEndAsync()
foreach ($r in $reqs[0..1]) { $p.StandardInput.WriteLine($r) }
$p.StandardInput.Close()
$null = $p.WaitForExit(30000)
$replies = @([regex]::Matches($outA.Result, '"jsonrpc"')).Count
Check 'A control: initialize + tools/list answered with stdout open' ($replies -ge 2) "replies=$replies"

$p = Start-Serve
$errB = $p.StandardError.ReadToEndAsync()
$p.StandardOutput.Close()          # the client is gone: every reply now hits a closed pipe
foreach ($r in $reqs) { try { $p.StandardInput.WriteLine($r) } catch { } }
try { $p.StandardInput.Close() } catch { }
$exited = $p.WaitForExit(30000)
if (-not $exited) { $p.Kill($true) }
Check 'B: the server exits on its own within 30 s' $exited ''
Check 'B: exit code 0, not the closed-pipe FATAL 3' ($exited -and $p.ExitCode -eq 0) "exit=$(if ($exited) { $p.ExitCode } else { 'killed' })"
Check 'B: no FATAL on stderr' ($errB.Result -notmatch 'FATAL') (($errB.Result -split "`n" | Select-String 'FATAL' | Select-Object -First 2) -join ' | ')
[IO.Directory]::Delete($WorkDir, $true)
if ($script:Failed) { exit 1 }
