#Requires -Version 7
# dl:serial: LSP proxy family. Spawns and reaps LspStub children; the sibling
#   proxy guards were observed interfering with each other even when strictly
#   serialised (root cause fixed in 41b0004), so this one joins the quarantine.
<#
  run_lsp_proxy_merge_completion_guard.ps1 -- `lsp --proxy --merge-completion`
  unions drag-lint's completion items into DelphiLSP's reply (merge plan A3;
  spec criteria 11-14, 19).

  Both sides are scripted: the P0 stub answers textDocument/completion from a
  script (with a delay when asked), and drag-lint answers from a fixture index
  passed with --db. The fixture's ON-DISK text has no member access at the
  member-request caret; the didOpen BUFFER does. So drag-lint items appear only
  when the proxy tapped didOpen into its live-document overlay -- the tap is
  under test, not assumed.

  Every request puts the caret MID-LINE with a character to its right, and the
  member request types a prefix after the dot (the standing lesson of
  Completion.pas: an end-of-line caret hides the off-by-one).

  Positive controls. Every "unchanged" case is paired with a case where the SAME
  engine does merge (1): a proxy that never merges fails the guard. The decoy
  FIx (a private field of an unrelated class) must be ABSENT from the member
  list, paired with a bare-identifier request that surfaces it -- so its absence
  is a filter, not a dead index. The dedup check is paired with a label that
  legitimately appears twice under two different kinds.

  Cases:
    1 both non-empty -> union, theirs first, ours appended when (label, kind)
      is absent, no duplicate pair; FIeld2 twice (kinds 10 and 5);
    2 theirs [] and theirs null -> drag-lint's items alone;
    3 ours empty (no didOpen: the disk text has no dot) -> theirs byte-identical;
    4 stub delay 200 ms, --merge-budget-ms 10 -> theirs byte-identical;
    5 OFF (--db, no --merge-completion) = the plain relay, byte for byte; ON
      (case 1) differs;
    6 bogus --db -> theirs byte-identical, exactly one stderr line names the
      merge;
    7 decoy: absent from the member list (1), present for the bare request;
    8 (A3 fix 3) requests with an empty position: relayed untouched, NO
      stderr line (A4 fix M2); a later valid request still merges;
    9 (A3 fix 2) a file no index owns: its own declarations are offered;
   10 (A3 fix 4) --db good --db missing: one stderr line names the missing
      path, the good index still merges.

  The proxy guards default -Exe to dll-win64; a lane passes its own engine.
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_lspproxy_mergecomp_$PID"
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

$StubEnvVars = @('DRAGLINT_STUB_PUBLISH_FILE', 'DRAGLINT_STUB_SCRIPT', 'DRAGLINT_STUB_LOG', 'DRAGLINT_STUB_LINGER', 'DRAGLINT_MERGE_TEST_EMPTY_REPLACEMENT')
foreach ($v in $StubEnvVars) { [Environment]::SetEnvironmentVariable($v, $null, 'Process') }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Invoke-Raw {
  param([string]$exe, [string[]]$argv, [byte[]]$c1, [hashtable]$envs = @{})
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName               = $exe
  foreach ($a in $argv) { [void]$psi.ArgumentList.Add($a) }
  foreach ($k in $envs.Keys) { $psi.Environment[$k] = $envs[$k] }
  $psi.WorkingDirectory       = $WorkDir
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
  $done = $p.WaitForExit(60000)
  if (-not $done) { try { $p.Kill($true) } catch { } }
  [void]$outT.Wait(5000); [void]$errT.Wait(5000)
  $code = if ($done) { $p.ExitCode } else { -999 }
  return [pscustomobject]@{ Out = $outMs.ToArray(); Err = $errMs.ToArray(); Code = $code }
}
function Ascii([byte[]]$b) { if (-not $b) { return '' } [System.Text.Encoding]::ASCII.GetString($b) }
function Utf8([byte[]]$b) { if (-not $b) { return '' } [System.Text.Encoding]::UTF8.GetString($b) }
function Frame([string]$body) {
  $bb = [System.Text.Encoding]::UTF8.GetBytes($body)
  $h  = [System.Text.Encoding]::ASCII.GetBytes("Content-Length: $($bb.Length)`r`n`r`n")
  return [byte[]]($h + $bb)
}
function Same([byte[]]$a, [byte[]]$b) {
  return ($a.Length -gt 0) -and ($a.Length -eq $b.Length) -and ($null -eq (Compare-Object $a $b -SyncWindow 0))
}
function Split-Frames([byte[]]$b) {
  $res = @()
  $s = Ascii $b
  $pos = 0
  while ($true) {
    $m = [regex]::Match($s.Substring($pos), '(?is)Content-Length:\s*(\d+)[^\r]*\r\n(?:[^\r]*\r\n)*?\r\n')
    if (-not $m.Success) { break }
    $start = $pos + $m.Index + $m.Length
    $decl  = [int]$m.Groups[1].Value
    $avail = [Math]::Min($decl, $b.Length - $start)
    $body  = [System.Text.Encoding]::UTF8.GetString($b, $start, $avail)
    $res  += [pscustomobject]@{ Declared = $decl; Actual = $avail; Body = $body }
    $pos   = $start + $avail
  }
  return ,$res
}
# The completion reply for request id 7: Frame, Items (array of hashtables, in
# order; $null when the result is null), IsNull.
function Reply7([byte[]]$b) {
  foreach ($f in (Split-Frames $b)) {
    try { $j = $f.Body | ConvertFrom-Json -AsHashtable } catch { continue }
    if ($j -and $j.ContainsKey('id') -and ($j['id'] -eq 7) -and $j.ContainsKey('result')) {
      $r = $j['result']
      $items = if ($null -eq $r) { $null } elseif ($r -is [System.Collections.IDictionary]) { @($r['items']) } else { @($r) }
      return [pscustomobject]@{ Frame = $f; Items = $items; IsNull = ($null -eq $r) }
    }
  }
  return $null
}
function Labels($items) { return @($items | Where-Object { $_ -is [System.Collections.IDictionary] } | ForEach-Object { $_['label'] }) }
function Pairs($items)  { return @($items | Where-Object { $_ -is [System.Collections.IDictionary] } | ForEach-Object { "$($_['label'])|$($_['kind'])" }) }
function Uri([string]$path) { return 'file:///' + ($path -replace '\\', '/') }

Write-Host ''
Write-Host 'run_lsp_proxy_merge_completion_guard -- completion merge (A3)' -ForegroundColor Cyan

# --- the stub server, built the same way the sibling guards build it --------
$fixtureDir = "$PSScriptRoot\fixtures\lspproxy"
$outDir     = Join-Path $WorkDir 'stub'
New-Item -ItemType Directory $outDir | Out-Null
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$null = cmd /c "call `"$rs`" && cd /d `"$fixtureDir`" && dcc64 -CC -E`"$outDir`" -N0`"$outDir`" LspStubServer.dpr" 2>&1
$stub = "$outDir\LspStubServer.exe"
Check 'LspStubServer.exe built' (Test-Path $stub) $stub
if (-not (Test-Path $stub)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

# --- the fixture unit and its index ------------------------------------------
# Line 25 (0-based) is "  Use;" on DISK and "  Foo.FI := 1;" in the didOpen
# BUFFER; line 26 is the bare-identifier line in both.
$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir | Out-Null
$unit = Join-Path $srcDir 'Fx.pas'
$head = @('unit Fx;', '', 'interface', '', 'type', '  TFoo = class', '  public', '    FIrst: Integer;', '    FIeld2: Integer;', '  end;',
          '', 'procedure Use;', '', 'implementation', '', 'type', '  THidden = class', '  private', '    FIx: Integer;', '  end;',
          '', 'procedure Use;', 'var', '  Foo: TFoo;', 'begin')
$tail = @('  Foo.FIrst:= FIx;', 'end;', '', 'end.', '')
$diskText = (($head + @('  Use;')          + $tail) -join "`r`n")
$bufText  = (($head + @('  Foo.FI := 1;')  + $tail) -join "`r`n")
[IO.File]::WriteAllText($unit, $diskText, [Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'fx.sqlite'
& $Exe index $srcDir --db $db 2>&1 | Out-Null
Check 'built the fixture index' (Test-Path $db)
$q = (& $Exe query --name FIx --db $db 2>$null | Out-String)
Check 'positive control: the index holds the decoy FIx' ($q -match 'FIx') ''
$uri = Uri $unit
$jsonText = ($bufText | ConvertTo-Json)
$didOpen  = Frame ('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"' + $uri + '","languageId":"pascal","version":1,"text":' + $jsonText + '}}}')
function CompReq([int]$line, [int]$ch) {
  return Frame ('{"jsonrpc":"2.0","id":7,"method":"textDocument/completion","params":{"textDocument":{"uri":"' + $uri + '"},"position":{"line":' + $line + ',"character":' + $ch + '}}}')
}
$memberReq = CompReq 25 8    # "  Foo.FI| := 1;"     (buffer) -- ' ' to the right
$bareReq   = CompReq 26 16   # "  Foo.FIrst:= FI|x;"  -- 'x' to the right
$script:ScriptN = 0
function Script([string]$result, [int]$delay = 0) {
  $script:ScriptN++
  $f = Join-Path $WorkDir "script$($script:ScriptN).tsv"
  [IO.File]::WriteAllText($f, "textDocument/completion`t$delay`t$result`r`n", [Text.Encoding]::ASCII)
  return @{ DRAGLINT_STUB_SCRIPT = $f }
}
$plainArgs = @('lsp', '--proxy', '--delphi-lsp', $stub)
$offArgs   = @('lsp', '--proxy', '--db', $db, '--merge-budget-ms', '20000', '--delphi-lsp', $stub)
$onArgs    = @('lsp', '--proxy', '--merge-completion', '--db', $db, '--merge-budget-ms', '20000', '--delphi-lsp', $stub)
$tightArgs = @('lsp', '--proxy', '--merge-completion', '--db', $db, '--merge-budget-ms', '10', '--delphi-lsp', $stub)
$bogusArgs = @('lsp', '--proxy', '--merge-completion', '--db', (Join-Path $WorkDir 'no-such.sqlite'), '--merge-budget-ms', '20000', '--delphi-lsp', $stub)

$theirs1 = '{"isIncomplete":false,"items":[{"label":"FIrst","kind":5},{"label":"FIeld2","kind":10},{"label":"StubOnly","kind":3}]}'

# --- 1 union -----------------------------------------------------------------
Write-Host ''
Write-Host '(1) both non-empty: union, theirs first, no duplicate (label, kind)' -ForegroundColor Cyan
$in1  = [byte[]]($didOpen + $memberReq)
$env1 = Script $theirs1
$r1   = Invoke-Raw $Exe $onArgs $in1 $env1
$p1   = Invoke-Raw $Exe $plainArgs $in1 $env1
$m1   = Reply7 $r1.Out
$it1  = if ($m1) { $m1.Items } else { @() }
$pr1  = Pairs $it1
Check 'reply for id 7 present' ($null -ne $m1) ''
Check 'theirs first, in order' (($pr1.Count -ge 3) -and ($pr1[0] -eq 'FIrst|5') -and ($pr1[1] -eq 'FIeld2|10') -and ($pr1[2] -eq 'StubOnly|3')) ("items=$($pr1 -join ',')")
Check 'drag-lint item appended: FIeld2 under kind 5 (same label, other kind: legitimately twice)' (@($pr1 | Where-Object { $_ -eq 'FIeld2|5' }).Count -eq 1 -and @(Labels $it1 | Where-Object { $_ -eq 'FIeld2' }).Count -eq 2) ("items=$($pr1 -join ',')")
Check 'no duplicate (label, kind): FIrst|5 exactly once' (@($pr1 | Where-Object { $_ -eq 'FIrst|5' }).Count -eq 1) ("items=$($pr1 -join ',')")
Check 'no duplicate pair anywhere' ($pr1.Count -gt 0 -and @($pr1 | Select-Object -Unique).Count -eq $pr1.Count) ''
Check 'Content-Length is exact' ($m1 -and $m1.Frame.Declared -eq $m1.Frame.Actual -and $m1.Frame.Declared -eq [Text.Encoding]::UTF8.GetByteCount($m1.Frame.Body)) ''
Check '(7) decoy FIx absent from the member list' ($m1 -and -not ((Labels $it1) -contains 'FIx')) ''

# --- 2 theirs empty / null ---------------------------------------------------
Write-Host ''
Write-Host '(2) theirs [] and theirs null: drag-lint items alone' -ForegroundColor Cyan
foreach ($t in @('[]', 'null')) {
  $r2  = Invoke-Raw $Exe $onArgs $in1 (Script $t)
  $m2  = Reply7 $r2.Out
  $pr2 = if ($m2 -and -not $m2.IsNull) { Pairs $m2.Items } else { @() }
  Check "theirs ${t}: FIrst|5 and FIeld2|5 present" (($pr2 -contains 'FIrst|5') -and ($pr2 -contains 'FIeld2|5')) ("items=$($pr2 -join ',')")
  Check "theirs ${t}: nothing but drag-lint items" ($pr2.Count -ge 2 -and -not ($pr2 -contains 'StubOnly|3') -and -not ((Labels $m2.Items) -contains 'FIx')) ("items=$($pr2 -join ',')")
}

# --- 3 ours empty ------------------------------------------------------------
Write-Host ''
Write-Host '(3) ours empty (no didOpen: the disk line has no dot): theirs byte-identical' -ForegroundColor Cyan
$env3 = Script $theirs1
$r3  = Invoke-Raw $Exe $onArgs    ([byte[]]$memberReq) $env3
$p3  = Invoke-Raw $Exe $plainArgs ([byte[]]$memberReq) $env3
Check 'ours empty: ON = plain relay' (Same $r3.Out $p3.Out) ("on=$($r3.Out.Length) plain=$($p3.Out.Length)")

# --- 4 budget ----------------------------------------------------------------
Write-Host ''
Write-Host '(4) stub delay 200 ms, --merge-budget-ms 10: theirs byte-identical' -ForegroundColor Cyan
$env4 = Script $theirs1 200
$r4  = Invoke-Raw $Exe $tightArgs $in1 $env4
$p4  = Invoke-Raw $Exe $plainArgs $in1 $env4
Check 'over budget: ON = plain relay' (Same $r4.Out $p4.Out) ("on=$($r4.Out.Length) plain=$($p4.Out.Length)")
Check 'it was the budget that declined (stderr names it), not an empty contribution' ((Utf8 $r4.Err) -match 'merge-completion over its 10 ms budget') ("err=$(Utf8 $r4.Err)")

# --- 5 OFF vs ON ---------------------------------------------------------------
Write-Host ''
Write-Host '(5) OFF is the plain relay; ON differs' -ForegroundColor Cyan
$r5 = Invoke-Raw $Exe $offArgs $in1 $env1
Check 'OFF (--db, no --merge-completion) = plain relay, byte for byte' (Same $r5.Out $p1.Out) ("off=$($r5.Out.Length) plain=$($p1.Out.Length)")
Check 'ON differs from the plain relay (positive control)' ($r1.Out.Length -gt 0 -and -not (Same $r1.Out $p1.Out)) ("on=$($r1.Out.Length) plain=$($p1.Out.Length)")
Check 'ON carries a drag-lint item (FIeld2|5)' ($pr1 -contains 'FIeld2|5') ''

# --- 6 bogus --db ---------------------------------------------------------------
Write-Host ''
Write-Host '(6) bogus --db: relay unharmed, one stderr line' -ForegroundColor Cyan
$r6 = Invoke-Raw $Exe $bogusArgs $in1 $env1
Check 'bogus --db: ON = plain relay' (Same $r6.Out $p1.Out) ("on=$($r6.Out.Length) plain=$($p1.Out.Length)")
$e6 = @((Utf8 $r6.Err) -split "\r?\n" | Where-Object { $_.Trim() -ne '' -and $_.Trim() -ne 'STUB-STDERR-LINE' })   # the stub's own stderr line is relayed
Check 'exactly one stderr line, and it names the merge' ($e6.Count -eq 1 -and $e6[0] -match 'merge disabled') ("lines=$($e6.Count) err=$(Utf8 $r6.Err)")

# --- 7 decoy surfaces for a bare identifier --------------------------------------
Write-Host ''
Write-Host '(7) the decoy surfaces for a bare-identifier request' -ForegroundColor Cyan
$r7  = Invoke-Raw $Exe $onArgs ([byte[]]($didOpen + $bareReq)) (Script '[]')
$m7  = Reply7 $r7.Out
$l7  = if ($m7 -and -not $m7.IsNull) { Labels $m7.Items } else { @() }
Check 'bare "FI": FIx offered (the index and the tap serve it)' ($l7 -contains 'FIx') ("labels=$($l7 -join ',')")

# --- 8 a request without line / character (A3 fix 3) -----------------------------
Write-Host ''
Write-Host '(8) completion requests with no position fields: relayed untouched, no stderr line' -ForegroundColor Cyan
function NoPosReq([int]$id) {
  return Frame ('{"jsonrpc":"2.0","id":' + $id + ',"method":"textDocument/completion","params":{"textDocument":{"uri":"' + $uri + '"},"position":{}}}')
}
$in8  = [byte[]]((NoPosReq 5) + (NoPosReq 6) + $didOpen + $memberReq)
$env8 = Script $theirs1
$r8   = Invoke-Raw $Exe $onArgs $in8 $env8
$m8   = Reply7 $r8.Out
$e8   = @((Utf8 $r8.Err) -split "\r?\n" | Where-Object { $_ -match 'could not record' })
Check 'two position-less requests: no stderr line about them' ($e8.Count -eq 0) ("lines=$($e8.Count) err=$(Utf8 $r8.Err)")
Check 'positive control: the later request 7 in the same session still merges' ($m8 -and ((Pairs $m8.Items) -contains 'FIeld2|5')) ''
$n8 = @(Split-Frames $r8.Out | ForEach-Object { try { $_.Body | ConvertFrom-Json -AsHashtable } catch { $null } } |
        Where-Object { $_ -and $_.ContainsKey('id') -and ($_['id'] -in 5, 6) -and $_.ContainsKey('result') } |
        ForEach-Object { @($_['result']['items']).Count })
Check 'replies 5 and 6 relayed with theirs only (3 items each)' ($n8.Count -eq 2 -and ($n8 | Where-Object { $_ -ne 3 }).Count -eq 0) ("counts=$($n8 -join ',')")

# --- 9 a file no index owns (A3 fix 2) ------------------------------------------------
Write-Host ''
Write-Host '(9) a file outside every index: its own declarations are offered' -ForegroundColor Cyan
$looseDir = Join-Path $WorkDir 'loose'
New-Item -ItemType Directory $looseDir | Out-Null
$loose = Join-Path $looseDir 'Lx.pas'
$looseText = (@('unit Lx;', '', 'interface', '', 'implementation', '', 'var', '  LooseCount: Integer;', '', 'procedure Run;', 'begin',
                '  LooseCount:= LooseC + 1;', 'end;', '', 'end.', '') -join "`r`n")
[IO.File]::WriteAllText($loose, $looseText, [Text.Encoding]::ASCII)
$looseUri  = Uri $loose
$looseOpen = Frame ('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"' + $looseUri + '","languageId":"pascal","version":1,"text":' + ($looseText | ConvertTo-Json) + '}}}')
$looseReq  = Frame ('{"jsonrpc":"2.0","id":7,"method":"textDocument/completion","params":{"textDocument":{"uri":"' + $looseUri + '"},"position":{"line":11,"character":21}}}')
$r9 = Invoke-Raw $Exe $onArgs ([byte[]]($looseOpen + $looseReq)) (Script '[]')
$m9 = Reply7 $r9.Out
$l9 = if ($m9 -and -not $m9.IsNull) { Labels $m9.Items } else { @() }
Check 'unowned file: LooseCount offered (StoresForFile, as plain lsp does)' ($l9 -contains 'LooseCount') ("labels=$($l9 -join ',')")

# --- 10 a --db list with one missing path (A3 fix 4) -----------------------------------
Write-Host ''
Write-Host '(10) --db good --db missing: merge still works, one stderr line names the missing path' -ForegroundColor Cyan
$missing  = Join-Path $WorkDir 'gone-a3fix.sqlite'
$mixArgs  = @('lsp', '--proxy', '--merge-completion', '--db', $db, '--db', $missing, '--merge-budget-ms', '20000', '--delphi-lsp', $stub)
$r10 = Invoke-Raw $Exe $mixArgs $in1 $env1
$m10 = Reply7 $r10.Out
$e10 = @((Utf8 $r10.Err) -split "\r?\n" | Where-Object { $_.Contains('gone-a3fix.sqlite') })
Check 'exactly one stderr line names the missing path' ($e10.Count -eq 1) ("lines=$($e10.Count) err=$(Utf8 $r10.Err)")
Check 'positive control: the good index still merges' ($m10 -and ((Pairs $m10.Items) -contains 'FIeld2|5')) ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\draglint_lspproxy_mergecomp_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
