<#
  run_mcp_args_leak.ps1 -- 1.39.1: a tools/call whose `arguments` is NOT an
  object must not leak.

  THE DEFECT. TMCPServer.DispatchToolsCall made a fresh empty TJSONObject when
  `arguments` was missing OR not an object, but its finally freed it only when
  `arguments` was MISSING. "arguments": "x" (or an array, a number) therefore
  leaked one TJSONObject (+ its member list) per call -- a long-lived `serve`
  driven by a sloppy client grows without bound.

  HOW IT IS MEASURED. One `serve` process; a warm-up batch, then two equal
  batches, each followed by a wait until every reply arrived and a read of the
  process's private bytes:
    batch A (CONTROL): "arguments": {}  -- owned by the request, never leaked;
    batch B (ASSERT) : "arguments": "x" -- the leaking shape.
  Growth over B must stay near growth over A. Before the fix B grows by tens of
  MB (N x ~100 bytes); the control proves the instrument can tell them apart.

  POSITIVE CONTROL: run against the 1.39.0 build -- the ASSERT fails.
  Usage: pwsh -File tests/autotest/run_mcp_args_leak.ps1 [-Exe <path>] [-N 150000]
#>
[CmdletBinding()]
param(
  [string]$Exe    = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$DbPath = "$PSScriptRoot\..\calls.sqlite",
  [int]$N         = 150000
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

$psi = [Diagnostics.ProcessStartInfo]::new($Exe)
foreach ($a in @('serve', '--db', (Resolve-Path $DbPath).Path)) { $psi.ArgumentList.Add($a) }
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.WorkingDirectory = $env:TEMP
$p = [Diagnostics.Process]::Start($psi)
# Drain stdout/stderr on .NET threads: a PowerShell event action per reply is far too slow for 300k lines.
Add-Type -TypeDefinition @"
using System.Diagnostics; using System.Threading;
public static class McpLeakDrain {
  public static int Replies;
  public static void Start(Process p) {
    new Thread(() => { string l; while ((l = p.StandardOutput.ReadLine()) != null) if (l.Contains("\"id\"")) Interlocked.Increment(ref Replies); }) { IsBackground = true }.Start();
    new Thread(() => { while (p.StandardError.ReadLine() != null) { } }) { IsBackground = true }.Start();
  }
}
"@
[McpLeakDrain]::Start($p)
$script:NextId = 1
function Batch([int]$Count, [string]$ArgsJson) {
  $target = [McpLeakDrain]::Replies + $Count
  $sb = [Text.StringBuilder]::new()
  for ($i = 0; $i -lt $Count; $i++) {
    [void]$sb.Append('{"jsonrpc":"2.0","id":').Append($script:NextId).Append(',"method":"tools/call","params":{"name":"no_such_tool","arguments":').Append($ArgsJson).Append("}}`n")
    $script:NextId++
    if ($sb.Length -gt 1MB) { $p.StandardInput.Write($sb.ToString()); [void]$sb.Clear() }
  }
  $p.StandardInput.Write($sb.ToString()); $p.StandardInput.Flush()
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ([McpLeakDrain]::Replies -lt $target -and $sw.Elapsed.TotalSeconds -lt 300 -and -not $p.HasExited) { Start-Sleep -Milliseconds 200 }
  [GC]::Collect()
  $p.Refresh()
  return [pscustomobject]@{ Replies = [McpLeakDrain]::Replies; Target = $target; Private = $p.PrivateMemorySize64 }
}

try {
  $w = Batch 20000 '{}'
  Check 'warm-up: every call answered' ($w.Replies -ge $w.Target) "replies=$($w.Replies)/$($w.Target)"
  $a = Batch $N '{}'
  $b = Batch $N '"x"'
  Check 'every call answered' ($b.Replies -ge $b.Target) "replies=$($b.Replies)/$($b.Target)"
  $growA = ($a.Private - $w.Private) / 1MB
  $growB = ($b.Private - $a.Private) / 1MB
  Write-Host ("  private bytes: warm={0:N1} MB  after {{}}={1:N1} MB (+{2:N1})  after ""x""={3:N1} MB (+{4:N1})" -f ($w.Private / 1MB), ($a.Private / 1MB), $growA, ($b.Private / 1MB), $growB)
  Check "CONTROL: $N calls with arguments {} grow private bytes < 8 MB" ($growA -lt 8) ("+{0:N1} MB" -f $growA)
  Check "ASSERT: $N calls with arguments ""x"" grow private bytes < 8 MB (no per-call leak)" ($growB -lt 8) ("+{0:N1} MB" -f $growB)
} finally {
  try { $p.StandardInput.Close() } catch {}
  if (-not $p.WaitForExit(30000)) { try { $p.Kill() } catch {} }
}
Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
