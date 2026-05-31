# drag-lint smoke autotest
#
# Drives drag-lint.exe and drag-lint.exe lsp the same way the IDE plugin
# does — outside the IDE — so regressions in the CLI, indexer, LSP server,
# and pipe-framing layer can be caught without launching RAD Studio.
#
# Exit code: 0 on full pass, non-zero on first failure.
#
# Usage:
#   pwsh -File tests/autotest/run_smoke.ps1
#   pwsh -File tests/autotest/run_smoke.ps1 -Exe path\to\drag-lint.exe
#
# Coverage:
#   1. drag-lint.exe --version reports the expected version string
#   2. drag-lint.exe index <fixture> --db <tmp.sqlite> succeeds + finds known symbols
#   3. drag-lint.exe query --name KnownMethod returns the indexed symbol
#   4. drag-lint.exe query find-callers --name KnownMethod returns >= 1 ref
#   5. drag-lint.exe hover --qname SampleUnit.TKnownClass.KnownMethod returns docs
#   6. LSP server spawn + initialize handshake round-trips within 3s (catches v0.40.1 regression)
#   7. LSP textDocument/hover returns a result for a known position
#   8. LSP shutdown + exit closes the process within 2s (catches v0.40.2 freeze)
#
# Anti-regression for known bugs:
#   - v0.36 arch mismatch        : --version returns clean (non-zero exit + 0xC0000135 message)
#   - v0.37 SQLite UPSERT        : index command exits 0
#   - v0.40.0 editor paint AV    : N/A here, only fires in IDE
#   - v0.40.0 IDE exit AV        : N/A here, only fires in IDE
#   - v0.40.1 log path mismatch  : N/A here, only fires in IDE dialogs
#   - v0.40.2 Stop hangs forever : LSP shutdown timing check

[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win32\drag-lint.exe",
    [string] $ExpectedVersion = '0.40.2-alpha',
    [string] $FixtureDir = "$PSScriptRoot\fixtures",
    [string] $WorkDir = "$env:TEMP\drag-lint-autotest",
    [int]    $InitTimeoutMs = 3000,
    [int]    $ShutdownTimeoutMs = 2000
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Results = @()

function Write-Check {
    param([string] $Name, [bool] $Ok, [string] $Detail = '', [double] $Ms = 0)
    $status = if ($Ok) { 'PASS' } else { 'FAIL' }
    $color  = if ($Ok) { 'Green' } else { 'Red' }
    $msStr  = if ($Ms -gt 0) { "{0,6:N0}ms" -f $Ms } else { '         ' }
    Write-Host ("  [{0}] {1} {2,-50} {3}" -f $status, $msStr, $Name, $Detail) -ForegroundColor $color
    $script:Results += [PSCustomObject]@{
        Name = $Name; Ok = $Ok; Detail = $Detail; Ms = $Ms
    }
    if (-not $Ok) { $script:Failed = $true }
}

function Run-Stage {
    param([string] $Name, [scriptblock] $Block)
    Write-Host "`n== $Name ==" -ForegroundColor Cyan
    & $Block
}

# --------------------------------------------------------------------------
# Set up clean work dir
# --------------------------------------------------------------------------

if (-not (Test-Path $Exe)) {
    Write-Host "FATAL: drag-lint.exe not found at $Exe" -ForegroundColor Red
    exit 2
}
if (-not (Test-Path $FixtureDir)) {
    Write-Host "FATAL: fixture dir not found: $FixtureDir" -ForegroundColor Red
    exit 2
}

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$db = "$WorkDir\fixture.sqlite"

Write-Host "drag-lint autotest harness" -ForegroundColor Cyan
Write-Host "  exe:          $Exe"
Write-Host "  expected ver: $ExpectedVersion"
Write-Host "  fixtures:     $FixtureDir"
Write-Host "  workdir:      $WorkDir"
Write-Host ""

# --------------------------------------------------------------------------
# Stage 1: CLI smoke
# --------------------------------------------------------------------------

Run-Stage 'CLI smoke' {

    $t0 = [Diagnostics.Stopwatch]::StartNew()
    $verOut = & $Exe --version 2>&1
    $t0.Stop()
    Write-Check '--version exits 0'        ($LASTEXITCODE -eq 0) $verOut $t0.Elapsed.TotalMilliseconds
    Write-Check '--version matches expected' ($verOut -match [Regex]::Escape($ExpectedVersion)) $verOut

    $t1 = [Diagnostics.Stopwatch]::StartNew()
    $indexOut = & $Exe index $FixtureDir --db $db 2>&1 | Select-Object -Last 1
    $t1.Stop()
    Write-Check 'index fixture exits 0' ($LASTEXITCODE -eq 0) $indexOut $t1.Elapsed.TotalMilliseconds
    Write-Check 'index reports >= 1 symbol' ($indexOut -match 'Symbols:\s*[1-9]\d*') $indexOut

    $t2 = [Diagnostics.Stopwatch]::StartNew()
    $qOut = & $Exe query --name KnownMethod --db $db 2>&1
    $t2.Stop()
    Write-Check 'query KnownMethod returns 1+ match' (($qOut | Select-String 'KnownMethod' -Quiet) -eq $true) "($($qOut.Count) lines)" $t2.Elapsed.TotalMilliseconds

    $t3 = [Diagnostics.Stopwatch]::StartNew()
    $fcOut = & $Exe query find-callers --name KnownMethod --db $db 2>&1
    $t3.Stop()
    Write-Check 'find-callers KnownMethod returns 1+ ref' (($fcOut | Select-String 'KnownMethod|SampleUnit' -Quiet) -eq $true) "($($fcOut.Count) lines)" $t3.Elapsed.TotalMilliseconds

    $t4 = [Diagnostics.Stopwatch]::StartNew()
    $hovOut = & $Exe hover --qname SampleUnit.TKnownClass.KnownMethod --db $db 2>&1
    $t4.Stop()
    Write-Check 'hover KnownMethod returns text' (($hovOut | Measure-Object -Character).Characters -gt 0) "($(($hovOut | Measure-Object -Character).Characters) chars)" $t4.Elapsed.TotalMilliseconds

    # v0.40.3: multi-DB query check. Index a second copy of the fixture into
    # a second sqlite (different file path), pass both --db flags, expect
    # results to be merged (at least 1 match each = 2+ total).
    $db2 = "$WorkDir\fixture2.sqlite"
    & $Exe index $FixtureDir --db $db2 2>&1 | Out-Null
    $t5 = [Diagnostics.Stopwatch]::StartNew()
    $mdbOut = & $Exe query --name KnownMethod --db $db --db $db2 2>&1
    $t5.Stop()
    Write-Check 'multi-DB query returns merged results' (($mdbOut | Select-String 'KnownMethod').Count -ge 2) "($(($mdbOut | Select-String 'KnownMethod').Count) KnownMethod lines)" $t5.Elapsed.TotalMilliseconds
}

# --------------------------------------------------------------------------
# Stage 2: LSP server — spawn + initialize + hover + shutdown
#
# This is the regression-catcher for the v0.40.1 freeze and the v0.40.2 Stop
# hang. If LSP can be spawned, initialized, hover-queried, and shut down
# cleanly within the timeouts, the plugin's pipe + framing layer works.
# --------------------------------------------------------------------------

Run-Stage 'LSP server smoke' {

    Add-Type -TypeDefinition @'
namespace DragLintAutotest
{
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public static class LspHarness
{
    public static int LastSpawnMs;
    public static int LastInitMs;
    public static int LastShutdownMs;
    public static string LastInitResponse;
    public static string LastHoverResponse;

    public static string RunSmoke(string exe, string db, string fixturePath, int initTimeoutMs, int shutdownTimeoutMs)
    {
        var psi = new ProcessStartInfo(exe, string.Format("lsp --db \"{0}\"", db));
        psi.RedirectStandardInput  = true;
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardError  = true;
        psi.UseShellExecute = false;
        psi.CreateNoWindow  = true;
        psi.StandardOutputEncoding = Encoding.UTF8;
        psi.StandardErrorEncoding  = Encoding.UTF8;

        var sw = Stopwatch.StartNew();
        var proc = Process.Start(psi);
        sw.Stop();
        LastSpawnMs = (int)sw.ElapsedMilliseconds;

        try
        {
            var rawOut = proc.StandardOutput.BaseStream;

            // initialize
            var initReq = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"processId\":null,\"rootUri\":null,\"capabilities\":{}}}";
            WriteFramed(proc.StandardInput.BaseStream, initReq);

            sw.Restart();
            LastInitResponse = ReadFramedWithTimeout(rawOut, initTimeoutMs);
            sw.Stop();
            LastInitMs = (int)sw.ElapsedMilliseconds;
            if (LastInitResponse == null) return "TIMEOUT_INIT";

            // textDocument/hover at a known position
            // SampleUnit.pas line 21 (0-based 20), column 14 = inside KnownMethod
            string uri = "file:///" + fixturePath.Replace('\\', '/');
            var hoverReq = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"" + uri + "\"},\"position\":{\"line\":20,\"character\":14}}}";
            WriteFramed(proc.StandardInput.BaseStream, hoverReq);
            LastHoverResponse = ReadFramedWithTimeout(rawOut, 2000);

            // shutdown + exit
            var shutdownReq = "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"shutdown\"}";
            WriteFramed(proc.StandardInput.BaseStream, shutdownReq);
            ReadFramedWithTimeout(rawOut, 1000);
            var exitReq = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";
            WriteFramed(proc.StandardInput.BaseStream, exitReq);

            sw.Restart();
            bool exited = proc.WaitForExit(shutdownTimeoutMs);
            sw.Stop();
            LastShutdownMs = (int)sw.ElapsedMilliseconds;
            if (!exited)
            {
                proc.Kill();
                return "TIMEOUT_SHUTDOWN";
            }
            return "OK";
        }
        catch (Exception e)
        {
            try { proc.Kill(); } catch {}
            return "ERROR: " + e.Message;
        }
    }

    static void WriteFramed(Stream s, string json)
    {
        var body = Encoding.UTF8.GetBytes(json);
        var header = Encoding.ASCII.GetBytes(string.Format("Content-Length: {0}\r\n\r\n", body.Length));
        s.Write(header, 0, header.Length);
        s.Write(body, 0, body.Length);
        s.Flush();
    }

    static string ReadFramedWithTimeout(Stream s, int timeoutMs)
    {
        var deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        var header = new MemoryStream();
        int contentLength = -1;
        var oneByte = new byte[1];
        int crlfState = 0;
        while (DateTime.UtcNow < deadline)
        {
            var task = s.ReadAsync(oneByte, 0, 1);
            int remainingMs = (int)(deadline - DateTime.UtcNow).TotalMilliseconds;
            if (remainingMs <= 0) return null;
            if (!task.Wait(remainingMs)) return null;
            int n = task.Result;
            if (n == 0) return null;
            byte b = oneByte[0];
            header.WriteByte(b);
            if (b == 13)      { if (crlfState == 0 || crlfState == 2) crlfState++; else crlfState = 1; }
            else if (b == 10) { if (crlfState == 1 || crlfState == 3) crlfState++; else crlfState = 0; }
            else              { crlfState = 0; }
            if (crlfState == 4) break;
        }

        string headerStr = Encoding.ASCII.GetString(header.ToArray());
        foreach (var line in headerStr.Split(new[] { "\r\n" }, StringSplitOptions.None))
        {
            if (line.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase))
            {
                int.TryParse(line.Substring("Content-Length:".Length).Trim(), out contentLength);
                break;
            }
        }
        if (contentLength <= 0) return null;

        var body = new byte[contentLength];
        int read = 0;
        while (read < contentLength && DateTime.UtcNow < deadline)
        {
            var task = s.ReadAsync(body, read, contentLength - read);
            int remainingMs = (int)(deadline - DateTime.UtcNow).TotalMilliseconds;
            if (remainingMs <= 0) return null;
            if (!task.Wait(remainingMs)) return null;
            int n = task.Result;
            if (n == 0) return null;
            read += n;
        }
        return Encoding.UTF8.GetString(body, 0, read);
    }
}
}
'@

    $fixturePath = (Resolve-Path "$FixtureDir\SampleUnit.pas").Path
    $result = [DragLintAutotest.LspHarness]::RunSmoke($Exe, $db, $fixturePath, $InitTimeoutMs, $ShutdownTimeoutMs)

    Write-Check 'LSP server spawns'   ([DragLintAutotest.LspHarness]::LastSpawnMs -lt 2000)               "" ([DragLintAutotest.LspHarness]::LastSpawnMs)
    Write-Check 'LSP initialize replies within timeout' ($result -ne 'TIMEOUT_INIT')     "result=$result" ([DragLintAutotest.LspHarness]::LastInitMs)
    Write-Check 'LSP initialize response is JSON-RPC'   ([DragLintAutotest.LspHarness]::LastInitResponse -match '"jsonrpc"\s*:\s*"2\.0"') "" 0
    Write-Check 'LSP capabilities object present'       ([DragLintAutotest.LspHarness]::LastInitResponse -match '"capabilities"')           "" 0
    Write-Check 'LSP hover round-trip'                  ([DragLintAutotest.LspHarness]::LastHoverResponse -ne $null)                        "" 0
    Write-Check 'LSP shutdown within timeout (no freeze regression)' ($result -ne 'TIMEOUT_SHUTDOWN') "result=$result" ([DragLintAutotest.LspHarness]::LastShutdownMs)
}

# --------------------------------------------------------------------------
# Summary + exit code
# --------------------------------------------------------------------------

$resultsDir = "$PSScriptRoot\results"
if (-not (Test-Path $resultsDir)) { New-Item -ItemType Directory $resultsDir | Out-Null }
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$jsonPath = "$resultsDir\$stamp-results.json"
$script:Results | ConvertTo-Json -Depth 5 | Set-Content $jsonPath -Encoding utf8

Write-Host ''
$passes = ($script:Results | Where-Object Ok).Count
$fails  = ($script:Results | Where-Object { -not $_.Ok }).Count
$summary = "{0} pass / {1} fail / {2} total" -f $passes, $fails, $script:Results.Count
$color = if ($script:Failed) { 'Red' } else { 'Green' }
Write-Host $summary -ForegroundColor $color
Write-Host "Detailed results: $jsonPath"
if ($script:Failed) { exit 1 } else { exit 0 }
