#Requires -Version 7
<#
  run_v152_ASYNC_hover.ps1 -- lane v152 ASYNC (ruling B9c): the deferred IDE hover.

  A client that announces a position (notification draglint/deferHover) gets the
  hoverBundle there in TWO steps: the fast sections at once with the
  'computing...' placeholder, then the whole bundle when it asks the same
  position again. The second step is cancellable: an announcement of another
  position or a $/cancelRequest of its id ends it with RequestCancelled (-32800)
  and no late result. Unannounced requests (the menu hover, MCP, batch callers)
  are answered whole, as before. Design:
  docs\superpowers\specs\2026-11-18-deferred-answers-design.md.

  The slow section is injected by DRAGLINT_TEST_HOVER_SLOW_MS (cancellable
  slices before the caller queries), so the timings below do not depend on the
  machine or the fixture size.

  Checks (fixture: Target called from CallerA and CallerB; Other uncalled):
    T1 announced first ask at Target: reply < 300 ms, result.deferred names the
       placeholder, model.facts carries it, no caller rows.
    T2 second ask at the same position: the whole bundle (no deferred key, both
       callers, no placeholder), and it took the injected slow time.
    T3 a move (announce Other + ask) during a second step: the new position's
       fast answer arrives < 300 ms, the abandoned request answers -32800 at
       once, and no late result for it arrives in the next 2.5 s.
    T4 $/cancelRequest of a running second step: -32800 within 300 ms.
    T5 an UNANNOUNCED ask elsewhere (the menu hover) during a second step does
       NOT abandon it: that step still delivers its whole result.
    W1-W4 the plugin side, by source: the protocol constants agree with the
       server's, the dwell announces before it asks, a partial answer is shown
       uncached and re-asked, and a tick drops a second step the user left.
  Positive controls:
    P1 an unannounced ask is answered whole and takes the injected slow time --
       the slow switch is live, so T1 / T3 being fast is not vacuous.
    P2 T2's late-arriving whole answer proves the listener catches a reply that
       comes seconds later -- T3's "no late reply" window is not deaf.
  RED: on the 1.52 base engine (no deferHover, no slow switch) T1 and P1 fail.

  Exit 0 on full pass, 1 on any failure, 2 when the harness cannot start.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-async-hover-$PID",
  [int]   $SlowMs  = 1500
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$FAST_MS       = 300
$CANCEL_MS     = 300
$LATE_WAIT_MS  = 2500
$PLACEHOLDER   = 'computing...'
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [IO.File]::WriteAllText($path, $t, (New-Object Text.ASCIIEncoding))
}

Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text;
using System.Threading;
public class AsyncHoverPipe {
  public class Msg { public string Json; public long Ms; }
  Process p;
  public BlockingCollection<Msg> Q = new BlockingCollection<Msg>();
  public Stopwatch Sw = Stopwatch.StartNew();
  public AsyncHoverPipe(string exe, string args, string workDir, string envName, string envValue) {
    var si = new ProcessStartInfo(exe, args);
    si.UseShellExecute = false;
    si.RedirectStandardInput = true;
    si.RedirectStandardOutput = true;
    si.RedirectStandardError = true;
    si.CreateNoWindow = true;
    si.WorkingDirectory = workDir;
    if (!string.IsNullOrEmpty(envName)) si.Environment[envName] = envValue;
    p = Process.Start(si);
    p.ErrorDataReceived += (s, e) => { };
    p.BeginErrorReadLine();
    var t = new Thread(ReadLoop); t.IsBackground = true; t.Start();
  }
  void ReadLoop() {
    var s = p.StandardOutput.BaseStream;
    try {
      while (true) {
        var hdr = new StringBuilder(); int b;
        while ((b = s.ReadByte()) >= 0) { hdr.Append((char)b); if (hdr.Length >= 4 && hdr.ToString(hdr.Length - 4, 4) == "\r\n\r\n") break; }
        if (b < 0) break;
        int len = 0;
        foreach (var line in hdr.ToString().Split(new[] { "\r\n" }, StringSplitOptions.RemoveEmptyEntries))
          if (line.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase)) len = int.Parse(line.Substring(15).Trim());
        var buf = new byte[len]; int got = 0;
        while (got < len) { int n = s.Read(buf, got, len - got); if (n <= 0) break; got += n; }
        Q.Add(new Msg { Json = Encoding.UTF8.GetString(buf, 0, got), Ms = Sw.ElapsedMilliseconds });
      }
    } catch (Exception) { }
    Q.CompleteAdding();
  }
  public void Send(string json) {
    var body = Encoding.UTF8.GetBytes(json);
    var head = Encoding.ASCII.GetBytes("Content-Length: " + body.Length + "\r\n\r\n");
    var s = p.StandardInput.BaseStream; s.Write(head, 0, head.Length); s.Write(body, 0, body.Length); s.Flush();
  }
  public Msg Next(int timeoutMs) { Msg m; return Q.TryTake(out m, timeoutMs) ? m : null; }
  public long Now { get { return Sw.ElapsedMilliseconds; } }
  public void Close() {
    try { p.StandardInput.Close(); } catch (Exception) { }
    if (!p.WaitForExit(15000)) { try { p.Kill(); } catch (Exception) { } }
  }
}
'@

$lsp = $null
try {
  if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
  $Exe = (Resolve-Path $Exe).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory $WorkDir | Out-Null
  $WorkDir = (Resolve-Path $WorkDir).Path
  $src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null
  $file = Join-Path $src 'uAsync.pas'
  WriteAnsi $file @'
unit uAsync;

interface

type
  TWorker = class
  public
    procedure Target;
    procedure Other;
    procedure CallerA;
    procedure CallerB;
  end;

implementation

procedure TWorker.Target;
begin
end;

procedure TWorker.Other;
begin
end;

procedure TWorker.CallerA;
begin
  Target;
end;

procedure TWorker.CallerB;
begin
  Target;
end;

end.
'@
  $db = Join-Path $WorkDir 'async.sqlite'
  & $Exe index $src --db $db 2>&1 | Out-Null
  Check 'fixture indexed' (Test-Path $db)

  $lines = [IO.File]::ReadAllLines($file)
  function PosOf([string]$pattern, [string]$word) {
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match $pattern) { return @{ line = $i; character = $lines[$i].IndexOf($word) + 1 } }
    }
    throw "fixture line not found: $pattern"
  }
  $td = @{ uri = 'file:///' + ($file -replace '\\', '/') }
  $pT = PosOf '^procedure TWorker\.Target;'  'Target'
  $pO = PosOf '^procedure TWorker\.Other;'   'Other'
  $pC = PosOf '^procedure TWorker\.CallerA;' 'CallerA'

  $lsp = New-Object AsyncHoverPipe($Exe, "lsp --db `"$db`"", $WorkDir, 'DRAGLINT_TEST_HOVER_SLOW_MS', [string]$SlowMs)
  $script:Seen = New-Object System.Collections.Generic.List[object]
  function J($o) { $o | ConvertTo-Json -Compress -Depth 10 }
  function Pump($ms) {
    $deadline = $lsp.Now + $ms
    while ($lsp.Now -lt $deadline) {
      $m = $lsp.Next([Math]::Max(1, [int]($deadline - $lsp.Now)))
      if ($null -eq $m) { continue }
      $o = $m.Json | ConvertFrom-Json
      $script:Seen.Add([pscustomobject]@{ o = $o; ms = $m.Ms })
    }
  }
  function WaitId($id, $ms) {
    $deadline = $lsp.Now + $ms
    while ($lsp.Now -lt $deadline) {
      $hit = @($script:Seen | Where-Object { $null -ne $_.o.id -and [string]$_.o.id -eq [string]$id })
      if ($hit.Count -gt 0) { return $hit[0] }
      $m = $lsp.Next(50)
      if ($null -eq $m) { continue }
      $script:Seen.Add([pscustomobject]@{ o = ($m.Json | ConvertFrom-Json); ms = $m.Ms })
    }
    return $null
  }
  function Defer($pos) { $lsp.Send((J @{ jsonrpc = '2.0'; method = 'draglint/deferHover'; params = @{ textDocument = $td; position = $pos } })) }
  function Ask($id, $pos) { $t = $lsp.Now; $lsp.Send((J @{ jsonrpc = '2.0'; id = $id; method = 'draglint/hoverBundle'; params = @{ textDocument = $td; position = $pos } })); return $t }
  function Raw($r) { if ($null -eq $r) { return 'no reply' }; return ($r.o | ConvertTo-Json -Compress -Depth 8) }
  function Facts($r) { if ($null -eq $r -or $null -eq $r.o.result -or $null -eq $r.o.result.model) { return @() }; return @($r.o.result.model.facts) }

  $lsp.Send((J @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ processId = $null; rootUri = $null; capabilities = @{} } }))
  $init = WaitId 1 60000
  Check 'engine initialized' ($null -ne $init)
  $lsp.Send((J @{ jsonrpc = '2.0'; method = 'initialized'; params = @{} }))

  # Warm-up (unannounced, elsewhere): opens the store and parses the file once.
  $tW = Ask 5 $pC
  $null = WaitId 5 30000

  # P1 positive control: unannounced = whole, and slow.
  $tP = Ask 6 $pT
  $rP = WaitId 6 30000
  $msP = if ($rP) { $rP.ms - $tP } else { -1 }
  Write-Host "  raw P1: $((Raw $rP).Substring(0, [Math]::Min(400, (Raw $rP).Length)))"
  Check 'P1 unannounced ask: whole answer (no deferred key, callers listed)' ($null -ne $rP -and $null -ne $rP.o.result -and $null -eq $rP.o.result.deferred -and @($rP.o.result.resolvedCallers).Count -ge 2) (Raw $rP)
  Check "P1 unannounced ask took the injected slow time (>= $($SlowMs - 100) ms)" ($msP -ge ($SlowMs - 100)) "ms=$msP"

  # T1 announced first ask: fast + placeholder.
  Defer $pT
  $t1 = Ask 10 $pT
  $r1 = WaitId 10 30000
  $ms1 = if ($r1) { $r1.ms - $t1 } else { -1 }
  Write-Host "  raw T1: $(Raw $r1)"
  Check "T1 announced first ask answered < $FAST_MS ms" ($ms1 -ge 0 -and $ms1 -lt $FAST_MS) "ms=$ms1"
  Check 'T1 result.deferred names the placeholder' ($null -ne $r1 -and $null -ne $r1.o.result.deferred -and $r1.o.result.deferred.placeholder -eq $PLACEHOLDER) (Raw $r1)
  Check 'T1 model.facts carries the placeholder line' ((Facts $r1) -contains $PLACEHOLDER) ("facts=" + ((Facts $r1) -join ' | '))
  Check 'T1 no caller rows yet' ($null -ne $r1 -and @($r1.o.result.resolvedCallers).Count -eq 0 -and @($r1.o.result.nameCallers).Count -eq 0)

  # T2 second ask, same position: whole and slow.
  $t2 = Ask 11 $pT
  $r2 = WaitId 11 30000
  $ms2 = if ($r2) { $r2.ms - $t2 } else { -1 }
  Check 'T2 second ask: the whole bundle (no deferred key, both callers)' ($null -ne $r2 -and $null -ne $r2.o.result -and $null -eq $r2.o.result.deferred -and @($r2.o.result.resolvedCallers).Count -ge 2) (Raw $r2)
  Check 'T2 no placeholder left in the facts' (-not ((Facts $r2) -contains $PLACEHOLDER)) ("facts=" + ((Facts $r2) -join ' | '))
  Check "P2/T2 the whole answer came late (>= $($SlowMs - 100) ms) and was still caught" ($ms2 -ge ($SlowMs - 100)) "ms=$ms2"

  # T3 a move during a second step.
  Defer $pT; $null = Ask 12 $pT; $null = WaitId 12 30000
  $null = Ask 13 $pT
  Pump 300
  Defer $pO
  $t14 = Ask 14 $pO
  $r14 = WaitId 14 30000
  $r13 = WaitId 13 30000
  $ms14 = if ($r14) { $r14.ms - $t14 } else { -1 }
  $ms13 = if ($r13) { $r13.ms - $t14 } else { -1 }
  Check "T3 the new position's first ask answered < $FAST_MS ms during the abandoned step" ($ms14 -ge 0 -and $ms14 -lt $FAST_MS -and $null -ne $r14.o.result.deferred) ("ms=$ms14 " + (Raw $r14))
  Check 'T3 the abandoned second step answered RequestCancelled (-32800)' ($null -ne $r13 -and $null -ne $r13.o.error -and $r13.o.error.code -eq -32800) (Raw $r13)
  Check "T3 ... within $CANCEL_MS ms of the move" ($ms13 -ge 0 -and $ms13 -lt $CANCEL_MS) "ms=$ms13"
  Pump $LATE_WAIT_MS
  $late = @($script:Seen | Where-Object { [string]$_.o.id -eq '13' })
  Check "T3 no late result for the abandoned request in $LATE_WAIT_MS ms" ($late.Count -eq 1 -and $null -eq $late[0].o.result) "replies=$($late.Count)"

  # T4 $/cancelRequest of a running second step (Other is armed by T3).
  $null = Ask 15 $pO
  Pump 200
  $t15 = $lsp.Now
  $lsp.Send((J @{ jsonrpc = '2.0'; method = '$/cancelRequest'; params = @{ id = 15 } }))
  $r15 = WaitId 15 30000
  $ms15 = if ($r15) { $r15.ms - $t15 } else { -1 }
  Check "T4 cancelRequest: -32800 within $CANCEL_MS ms" ($null -ne $r15 -and $null -ne $r15.o.error -and $r15.o.error.code -eq -32800 -and $ms15 -lt $CANCEL_MS) ("ms=$ms15 " + (Raw $r15))

  # T5 an unannounced ask elsewhere does not abandon a second step.
  Defer $pT; $null = Ask 16 $pT; $null = WaitId 16 30000
  $null = Ask 17 $pT
  Pump 200
  $null = Ask 18 $pO
  $r18 = WaitId 18 30000
  $r17 = WaitId 17 30000
  Check 'T5 the unannounced ask elsewhere is answered whole' ($null -ne $r18 -and $null -ne $r18.o.result -and $null -eq $r18.o.result.deferred) (Raw $r18)
  Check 'T5 the running second step still delivers its whole result' ($null -ne $r17 -and $null -ne $r17.o.result -and @($r17.o.result.resolvedCallers).Count -ge 2) (Raw $r17)

  $lsp.Send((J @{ jsonrpc = '2.0'; id = 2; method = 'shutdown'; params = @{} }))
  $null = WaitId 2 15000
  $lsp.Send((J @{ jsonrpc = '2.0'; method = 'exit'; params = @{} }))

  # W: the RAD Studio plugin's side (source pins; the IDE is not driven here).
  $root = (Resolve-Path "$PSScriptRoot\..\..").Path
  $ht = [IO.File]::ReadAllText("$root\src\delphi-plugin\DragLint.Plugin.HoverTracker.pas")
  $df = [IO.File]::ReadAllText("$root\src\lsp\DRagLint.LSP.Deferred.pas")
  foreach ($c in 'DEFER_HOVER_METHOD', 'DEFERRED_PLACEHOLDER') {
    $pat = "(?m)^\s*$c\s*=\s*'([^']*)';"
    $a = [regex]::Match($ht, $pat); $b = [regex]::Match($df, $pat)
    Check "W1 $c is the same text in the plugin and the server" ($a.Success -and $b.Success -and $a.Groups[1].Value -eq $b.Groups[1].Value) ("plugin=" + $a.Groups[1].Value + " server=" + $b.Groups[1].Value)
  }
  Check 'W2 the dwell announces before it asks (AnnounceDeferredHover precedes RequestHoverBundleAsync in OnTick)' `
    ($ht -match '(?s)if FInflightAnnounced then AnnounceDeferredHover\(Client, Uri, CaretRow, CaretCol\);\s*FInflightId:= if HoverBundleUnsupported then RequestHoverTextAsync\(.*?else RequestHoverBundleAsync\(') ''
  Check 'W3 a partial first answer is shown, NOT cached, and the same position asked again' `
    ($ht -match '(?s)if WasFirst and \(AStatus = hvsOk\) and IsDeferredFirstAnswer\(AModel\) then\s*begin\s*if not GateAndShowInflight\(AMarkdown, AModel, ACallers\) then.*?FInflightId:= RequestHoverBundleAsync\(FInflightUri, FInflightRow, FInflightCol, OnHoverBundleAnswer\);.*?Exit;\s*end;\s*FInflightClient\s*:= nil;\s*FLastLspKey') ''
  Check 'W4 every tick drops a second step the user moved on from (DropAbandonedSecondStep -> CancelInflight)' `
    (($ht -match '(?s)GetCursorPos\(Pos\);\s*\{[^}]*\}\s*DropAbandonedSecondStep;') -and ($ht -match '(?s)procedure TDragLintHoverHelper\.DropAbandonedSecondStep;.*?CancelInflight;\s*end;')) ''
}
catch {
  Check "runner: $($_.Exception.Message)" $false
}
finally {
  if ($null -ne $lsp) { $lsp.Close() }
  if (-not $script:Failed -and (Test-Path $WorkDir)) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
if ($script:Failed) { Write-Host 'run_v152_ASYNC_hover: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_v152_ASYNC_hover: PASS' -ForegroundColor Green
exit 0
