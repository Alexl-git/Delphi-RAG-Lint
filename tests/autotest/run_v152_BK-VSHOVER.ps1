#Requires -Version 7
<#
  run_v152_BK-VSHOVER.ps1 -- lane v152 BK-VSHOVER: B32 (deferred hover for VS Code),
  B43 (VS Code runs the drag-lint.disableRule code action) and B51 (hover writer list
  in the markdown hover, ISymbolStore path accessor, 'and N more').

  Server side (LSP textDocument/hover, the request VS Code sends):
    P1 an UNANNOUNCED hover is answered whole (facts, no placeholder) and takes the
       injected slow time -- the switch is live, so V1 being fast is not vacuous.
    V1 after draglint/deferHover the first hover at that position is the FAST step:
       < 300 ms, the markdown carries the 'computing...' placeholder, no facts yet.
    V2 the second hover at the same position is the whole markdown (facts, no
       placeholder), and it took the injected slow time.
    V3 $/cancelRequest of a running second step: RequestCancelled (-32800) < 300 ms.
    V4 an announcement of another position during a second step abandons it (-32800).
    S1 the whole hover on a unit variable with 7 writers lists 'Set by:' rows and
       'Set by: and 2 more' (B51: the VS Code markdown lacked the writer list).
    S2 the fast step of that hover has no 'Set by:' line (the solve is deferred).
    S3 HoverModel reads the index path through ISymbolStore.DbPath, not RTTI.
    A1 textDocument/codeAction on a drag-lint finding offers 'disable in this unit'
       and 'disable in this project' carrying command drag-lint.disableRule with
       [rule, scope, file, line] (B43 server half, the INT6 stash).
  Client side (editors\vscode\drag-lint):
    N1 test\deferredhover.test.js and test\disablerule.test.js pass under node.
    E1 the argv lib\disablerule.js builds is accepted by the engine's `rules disable`
       for unit and project scope and writes the overrides (end to end, no VS Code).
    W1 lib\deferredhover.js uses the same method + placeholder text as the server.
    W2 extension.js registers drag-lint.disableRule, and its provideHover middleware
       announces the position before it asks.
  RED: on the lane base engine V1/V2/S1/S3/A1 fail and the client files do not exist.

  Exit 0 on full pass, 1 on any failure, 2 when the harness cannot start.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-vshover-$PID",
  [int]   $SlowMs  = 1500
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Pass = 0
$script:Fail = 0
$FAST_MS      = 300
$CANCEL_MS    = 300
$PLACEHOLDER  = 'computing...'
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if ($ok) { $script:Pass++ } else { $script:Fail++; $script:Failed = $true }
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
public class VsHoverPipe {
  public class Msg { public string Json; public long Ms; }
  Process p;
  public BlockingCollection<Msg> Q = new BlockingCollection<Msg>();
  public Stopwatch Sw = Stopwatch.StartNew();
  public VsHoverPipe(string exe, string args, string workDir, string envName, string envValue) {
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

$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$vsDir = Join-Path $root 'editors\vscode\drag-lint'
$lsp = $null
try {
  if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
  $Exe = (Resolve-Path $Exe).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory $WorkDir | Out-Null
  $WorkDir = (Resolve-Path $WorkDir).Path
  $src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null
  $file = Join-Path $src 'uVsHover.pas'
  WriteAnsi $file @'
unit uVsHover;

interface

type
  TWorker = class
  public
    procedure Target;
    procedure Other;
    procedure CallerA;
    procedure CallerB;
  end;

var
  GCount: Integer;

procedure W1;
procedure W2;
procedure W3;
procedure W4;
procedure W5;
procedure W6;
procedure W7;

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

procedure W1;
begin
  GCount:= 1;
end;

procedure W2;
begin
  GCount:= 2;
end;

procedure W3;
begin
  GCount:= 3;
end;

procedure W4;
begin
  GCount:= 4;
end;

procedure W5;
begin
  GCount:= 5;
end;

procedure W6;
begin
  GCount:= 6;
end;

procedure W7;
begin
  GCount:= 7;
end;

end.
'@
  $db = Join-Path $WorkDir 'vshover.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $Exe index $src --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
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
  $pG = PosOf '^  GCount: Integer;'          'GCount'

  $lsp = New-Object VsHoverPipe($Exe, "lsp --db `"$db`"", $WorkDir, 'DRAGLINT_TEST_HOVER_SLOW_MS', [string]$SlowMs)
  $script:Seen = New-Object System.Collections.Generic.List[object]
  function J($o) { $o | ConvertTo-Json -Compress -Depth 10 }
  function Pump($ms) {
    $deadline = $lsp.Now + $ms
    while ($lsp.Now -lt $deadline) {
      $m = $lsp.Next([Math]::Max(1, [int]($deadline - $lsp.Now)))
      if ($null -eq $m) { continue }
      $script:Seen.Add([pscustomobject]@{ o = ($m.Json | ConvertFrom-Json); ms = $m.Ms })
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
  function Ask($id, $pos) { $t = $lsp.Now; $lsp.Send((J @{ jsonrpc = '2.0'; id = $id; method = 'textDocument/hover'; params = @{ textDocument = $td; position = $pos } })); return $t }
  function HoverMd($r) { if ($null -eq $r -or $null -eq $r.o.result -or $null -eq $r.o.result.contents) { return '' }; return [string]$r.o.result.contents.value }
  function Raw($r) { if ($null -eq $r) { return 'no reply' }; $s = ($r.o | ConvertTo-Json -Compress -Depth 8); return $s.Substring(0, [Math]::Min(600, $s.Length)) }
  function HasCalledFrom($md) { return $md -match 'Called from' }

  $lsp.Send((J @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ processId = $null; rootUri = $null; capabilities = @{} } }))
  $init = WaitId 1 60000
  Check 'engine initialized' ($null -ne $init)
  $lsp.Send((J @{ jsonrpc = '2.0'; method = 'initialized'; params = @{} }))

  # Warm-up (unannounced, elsewhere): opens the store and parses the file once.
  $null = Ask 5 $pC
  $null = WaitId 5 30000

  # P1 positive control: unannounced = whole and slow.
  $tP = Ask 6 $pT
  $rP = WaitId 6 30000
  $msP = if ($rP) { $rP.ms - $tP } else { -1 }
  Check 'P1 unannounced hover: whole markdown (Called from, no placeholder)' ((HasCalledFrom (HoverMd $rP)) -and -not ((HoverMd $rP).Contains($PLACEHOLDER))) (Raw $rP)
  Check "P1 unannounced hover took the injected slow time (>= $($SlowMs - 100) ms)" ($msP -ge ($SlowMs - 100)) "ms=$msP"

  # V1 announced first ask: fast + placeholder.
  Defer $pT
  $t1 = Ask 10 $pT
  $r1 = WaitId 10 30000
  $ms1 = if ($r1) { $r1.ms - $t1 } else { -1 }
  Check "V1 announced first hover answered < $FAST_MS ms" ($ms1 -ge 0 -and $ms1 -lt $FAST_MS) "ms=$ms1"
  Check 'V1 the markdown carries the placeholder and no facts yet' ((HoverMd $r1).Contains($PLACEHOLDER) -and -not (HasCalledFrom (HoverMd $r1))) (Raw $r1)

  # V2 second ask at the same position: whole and slow.
  $t2 = Ask 11 $pT
  $r2 = WaitId 11 30000
  $ms2 = if ($r2) { $r2.ms - $t2 } else { -1 }
  Check 'V2 second hover: the whole markdown (Called from, no placeholder)' ((HasCalledFrom (HoverMd $r2)) -and -not ((HoverMd $r2).Contains($PLACEHOLDER))) (Raw $r2)
  Check "V2 the whole answer took the injected slow time (>= $($SlowMs - 100) ms)" ($ms2 -ge ($SlowMs - 100)) "ms=$ms2"

  # R1 the client's split over these REAL replies: the companion part is the facts, not the footer.
  $dhLib = Join-Path $vsDir 'lib\deferredhover.js'
  if ((Test-Path $dhLib) -and (Get-Command node -ErrorAction SilentlyContinue)) {
    $fA = Join-Path $WorkDir 'v1.md'; $fB = Join-Path $WorkDir 'v2.md'
    [IO.File]::WriteAllText($fA, (HoverMd $r1)); [IO.File]::WriteAllText($fB, (HoverMd $r2))
    $js = "const d=require('$($dhLib -replace '\\','/')');const fs=require('fs');const a=fs.readFileSync(process.argv[1],'utf8'),b=fs.readFileSync(process.argv[2],'utf8');const s=d.fastPart(a);process.stdout.write(JSON.stringify({shown:s,rest:d.remainder(s,b)}));"
    $split = & node -e $js $fA $fB | ConvertFrom-Json
    Check 'R1 fast part shown: no placeholder, footer kept' (-not $split.shown.Contains($PLACEHOLDER) -and $split.shown -match 'context:') $split.shown
    Check 'R1 companion part: the Called from fact, no footer repeated' ($split.rest -match 'Called from' -and $split.rest -notmatch 'context:') $split.rest
  } else { Check 'R1 lib\deferredhover.js + node present' $false '' }

  # V3 $/cancelRequest of a running second step.
  Defer $pT; $null = Ask 12 $pT; $null = WaitId 12 30000
  $null = Ask 13 $pT
  Pump 200
  $t13 = $lsp.Now
  $lsp.Send((J @{ jsonrpc = '2.0'; method = '$/cancelRequest'; params = @{ id = 13 } }))
  $r13 = WaitId 13 30000
  $ms13 = if ($r13) { $r13.ms - $t13 } else { -1 }
  Check "V3 cancelRequest: -32800 within $CANCEL_MS ms" ($null -ne $r13 -and $null -ne $r13.o.error -and $r13.o.error.code -eq -32800 -and $ms13 -lt $CANCEL_MS) ("ms=$ms13 " + (Raw $r13))

  # V4 an announcement elsewhere abandons a running second step.
  Defer $pT; $null = Ask 14 $pT; $null = WaitId 14 30000
  $null = Ask 15 $pT
  Pump 200
  Defer $pO
  $null = Ask 16 $pO
  $r15 = WaitId 15 30000
  $r16 = WaitId 16 30000
  Check 'V4 a move abandons the second step (-32800)' ($null -ne $r15 -and $null -ne $r15.o.error -and $r15.o.error.code -eq -32800) (Raw $r15)
  Check 'V4 the new position gets its fast step' ((HoverMd $r16).Contains($PLACEHOLDER)) (Raw $r16)

  # S1/S2 the writer list in the markdown hover.
  $null = Ask 20 $pG
  $r20 = WaitId 20 60000
  $md20 = HoverMd $r20
  $setBy = @(($md20 -split "`n") | Where-Object { $_ -match 'Set by: [A-Za-z]' -and $_ -notmatch 'and \d+ more' })
  Check 'S1 whole hover on GCount lists 5 Set by: rows' ($setBy.Count -eq 5) ("rows=$($setBy.Count) " + (Raw $r20))
  Check "S1 ... and 'Set by: and 2 more'" ($md20 -match 'Set by: and 2 more') (Raw $r20)
  Defer $pG
  $null = Ask 21 $pG
  $r21 = WaitId 21 30000
  Check 'S2 the fast step has no Set by: line' ((HoverMd $r21).Contains($PLACEHOLDER) -and -not ((HoverMd $r21) -match 'Set by:')) (Raw $r21)

  # A1 the disable-rule code actions.
  $pE = PosOf '^procedure W1;' 'W1'
  $diag = @{ range = @{ start = @{ line = $pE.line; character = 0 }; end = @{ line = $pE.line; character = 5 } }; severity = 2; code = 'empty-except'; source = 'drag-lint'; message = 'x' }
  $lsp.Send((J @{ jsonrpc = '2.0'; id = 30; method = 'textDocument/codeAction'; params = @{ textDocument = $td; range = $diag.range; context = @{ diagnostics = @($diag) } } }))
  $r30 = WaitId 30 30000
  $acts = @(if ($r30 -and $r30.o.result) { $r30.o.result | Where-Object { $_.command -and $_.command.command -eq 'drag-lint.disableRule' } })
  $scopes = @($acts | ForEach-Object { $_.command.arguments[1] })
  Check 'A1 code actions offer drag-lint.disableRule for unit and project' ($acts.Count -eq 2 -and ($scopes -contains 'unit') -and ($scopes -contains 'project')) (Raw $r30)
  $all = @(if ($r30 -and $r30.o.result) { $r30.o.result })
  $isDis = @($all | ForEach-Object { $null -ne $_.command -and $_.command.command -eq 'drag-lint.disableRule' })
  $firstDis = [Array]::IndexOf($isDis, $true); $lastOther = [Array]::LastIndexOf($isDis, $false)
  Check 'A1 the disable actions come LAST (Fix finding applies the first quickfix)' ($firstDis -ge 0 -and $lastOther -ge 0 -and $firstDis -gt $lastOther) ("order=" + (($all | ForEach-Object { $_.title }) -join ' | '))
  $a0 = if ($acts.Count -gt 0) { $acts[0].command.arguments } else { @() }
  Check 'A1 arguments are [rule, scope, file, line(1-based)]' ($a0.Count -eq 4 -and $a0[0] -eq 'empty-except' -and ([string]$a0[2]) -ieq $file -and [int]$a0[3] -eq ($pE.line + 1)) ("args=" + ($a0 -join ' | '))

  $lsp.Send((J @{ jsonrpc = '2.0'; id = 2; method = 'shutdown'; params = @{} }))
  $null = WaitId 2 15000
  $lsp.Send((J @{ jsonrpc = '2.0'; method = 'exit'; params = @{} }))
  $lsp.Close(); $lsp = $null

  # S3 source pin.
  $hm = [IO.File]::ReadAllText("$root\src\query\DRagLint.Query.HoverModel.pas")
  $ci = [IO.File]::ReadAllText("$root\src\core\DRagLint.Core.Interfaces.pas")
  Check 'S3 HoverModel no longer reads FConn by RTTI' (-not ($hm -match "GetField\('FConn'\)") -and -not ($hm -match 'System\.Rtti')) ''
  Check 'S3 the index path comes from a DbPath accessor declared in Core.Interfaces' (($ci -match '(?m)^\s*function DbPath: string;') -and ($hm -match '\.DbPath')) ''

  # N1 node tests.
  $node = Get-Command node -ErrorAction SilentlyContinue
  if ($null -eq $node) { Check 'N1 node on PATH' $false 'node not found' }
  else {
    foreach ($t in 'deferredhover', 'disablerule') {
      $tf = Join-Path $vsDir "test\$t.test.js"
      $out = if (Test-Path $tf) { & { $ErrorActionPreference = 'Continue'; & node $tf 2>&1 | ForEach-Object { "$_" } } | Out-String } else { 'missing' }
      Check "N1 $t.test.js passes" ((Test-Path $tf) -and $LASTEXITCODE -eq 0 -and $out -match 'all assertions passed') $out
    }

    # E1 the extension's argv against the real engine.
    $lib = Join-Path $vsDir 'lib\disablerule.js'
    if (-not (Test-Path $lib)) { Check 'E1 lib\disablerule.js exists' $false '' }
    else {
      WriteAnsi (Join-Path $WorkDir 'drag-lint-lint.json') "{`n}`n"
      $libJs = ($lib -replace '\\', '/')
      foreach ($sc in 'unit', 'project') {
        $js = "const d=require('$libJs');process.stdout.write(JSON.stringify(d.buildArgs({rule:'empty-except',scope:'$sc',file:process.argv[1],line:5,reason:'lane test'})));"
        $argv = (& node -e $js $file | ConvertFrom-Json)
        $out = & { $ErrorActionPreference = 'Continue'; & $Exe @argv 2>&1 | ForEach-Object { "$_" } } | Out-String
        $code = $LASTEXITCODE
        $cfg = [IO.File]::ReadAllText((Join-Path $WorkDir 'drag-lint-lint.json'))
        $want = if ($sc -eq 'unit') { '"exclude_units"\s*:\s*\[\s*"uVsHover"' } else { '"enabled"\s*:\s*false' }
        Check "E1 $sc scope: the engine accepts the extension's argv (exit 0) and writes the override" ($code -eq 0 -and $cfg -match $want) ("argv=" + ($argv -join ' ') + " exit=$code out=$out cfg=$cfg")
        $parsed = & node -e "const d=require('$libJs');const r=d.describeResult(process.argv[1], 0);process.stdout.write(JSON.stringify(r));" $out | ConvertFrom-Json
        Check "E1 $sc scope: describeResult reads the engine's --json answer as done" ($parsed.ok -eq $true -and [string]$parsed.message -ne '') ($parsed | ConvertTo-Json -Compress)
      }
    }
  }

  # W1/W2 client source pins.
  $dh = Join-Path $vsDir 'lib\deferredhover.js'
  $df = [IO.File]::ReadAllText("$root\src\lsp\DRagLint.LSP.Deferred.pas")
  foreach ($pair in @(@('DEFER_HOVER_METHOD', 'DEFER_METHOD'), @('DEFERRED_PLACEHOLDER', 'PLACEHOLDER'))) {
    $b = [regex]::Match($df, "(?m)^\s*$($pair[0])\s*=\s*'([^']*)';")
    $a = if (Test-Path $dh) { [regex]::Match([IO.File]::ReadAllText($dh), "(?m)^const $($pair[1]) = '([^']*)';") } else { [regex]::Match('', 'x') }
    Check "W1 $($pair[1]) in lib\deferredhover.js equals the server's $($pair[0])" ($a.Success -and $b.Success -and $a.Groups[1].Value -eq $b.Groups[1].Value) ("client=" + $a.Groups[1].Value + " server=" + $b.Groups[1].Value)
  }
  $ext = [IO.File]::ReadAllText((Join-Path $vsDir 'extension.js'))
  Check 'W2 extension.js registers drag-lint.disableRule' ($ext -match "registerCommand\(disablerule\.COMMAND") ''
  Check 'W2 provideHover middleware announces (deferHover) before it asks (next)' ($ext -match '(?s)provideHover:\s*async \(document, position, token, next\) =>.*?sendNotification\(deferredhover\.DEFER_METHOD.*?next\(document, position, token\)') ''
}
catch {
  Check "runner: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" $false
}
finally {
  if ($null -ne $lsp) { $lsp.Close() }
  if (-not $script:Failed -and (Test-Path $WorkDir)) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
Write-Host ("run_v152_BK-VSHOVER: {0} pass, {1} fail" -f $script:Pass, $script:Fail)
if ($script:Failed) { Write-Host 'run_v152_BK-VSHOVER: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_v152_BK-VSHOVER: PASS' -ForegroundColor Green
