#Requires -Version 7
# dl:serial: LSP proxy family. Spawns and reaps LspStub children; the sibling
#   proxy guards were observed interfering with each other even when strictly
#   serialised (root cause fixed in 41b0004), so this one joins the quarantine.
<#
  run_lsp_proxy_merge_hover_guard.ps1 -- `lsp --proxy --merge-hover` merges
  drag-lint's hover facts into DelphiLSP's hover reply (merge plan A4; spec
  criteria 15, 16).

  Both sides are scripted: the P0 stub answers textDocument/hover from a
  script (with a delay when asked), and drag-lint answers from a fixture index
  passed with --db. The caret sits MID-WORD on the field FIrst, so drag-lint
  has a hover; an empty line gives it none.

  Contract pinned here:
    theirs present + ours  -> contents = MarkupContent markdown,
                              value = theirs + LF LF '---' LF LF + ours;
                              any other field of theirs (range) is kept;
    theirs MarkedString    -> normalised to markdown FIRST: a string stays as
      (string / {language,    is; {language, value} becomes a fenced block
      value} / array)         ```language LF value LF ```; an array joins its
                              normalised parts with LF LF;
    theirs null + ours     -> {contents:{kind:markdown, value: ours}};
    neither                -> null, byte-identical to the plain relay;
    theirs + ours empty    -> byte-identical;
    over budget            -> byte-identical, one stderr line names it.

  Positive controls. "ours" is not assumed: case 3 (theirs null) captures it,
  and case 1 must equal theirs + separator + EXACTLY that text. Every
  byte-identical case is paired with a case where the SAME engine merges, so a
  proxy that never merges fails the guard; OFF is paired with ON.

  Cases:
    1 (15) theirs MarkupContent + ours -> joined, range kept;
    2      theirs MarkedString string / object / array -> normalised, joined;
    3 (16a) theirs null + ours -> ours alone as MarkupContent;
    4 (16b) neither -> null forwarded byte-identical;
    5      ours empty, theirs present -> byte-identical;
    6      OFF (--db, no --merge-hover) = plain relay; ON differs;
    7      stub delay 200 ms, --merge-budget-ms 10 -> byte-identical;
    8      (A4 fix M2) hovers with an empty position: relayed untouched, no
           stderr line; a later valid hover still merges;
    9      (A4 fix M3) more hovers than the worker queue holds, while the
           index opens: an overflowed request is dropped from the id table,
           so its reply is forwarded at once and no over-budget line is
           written. 56 requests in one write against a queue of 8 force the
           overflow; a run where none overflowed FAILS (A5 fix M5), so the
           case can never pass vacuously.

  The proxy guards default -Exe to dll-win64; a lane passes its own engine.
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_lspproxy_mergehover_$PID"
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
# The hover reply for request id 7: Frame, Result (hashtable or $null), IsNull,
# Kind / Value of result.contents (when it is a MarkupContent object).
function Reply7([byte[]]$b) {
  foreach ($f in (Split-Frames $b)) {
    try { $j = $f.Body | ConvertFrom-Json -AsHashtable } catch { continue }
    if ($j -and $j.ContainsKey('id') -and ($j['id'] -eq 7) -and $j.ContainsKey('result')) {
      $r = $j['result']
      $kind = $null; $val = $null
      if (($r -is [System.Collections.IDictionary]) -and ($r['contents'] -is [System.Collections.IDictionary])) {
        $kind = $r['contents']['kind']; $val = $r['contents']['value']
      }
      return [pscustomobject]@{ Frame = $f; Result = $r; IsNull = ($null -eq $r); Kind = $kind; Value = $val }
    }
  }
  return $null
}
function Uri([string]$path) { return 'file:///' + ($path -replace '\\', '/') }
function Show([string]$s) { if ($null -eq $s) { return '<null>' } return ($s -replace "`n", '\n') }

Write-Host ''
Write-Host 'run_lsp_proxy_merge_hover_guard -- hover merge (A4)' -ForegroundColor Cyan

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
# Line 12 (0-based) is "  Foo.FIrst:= 1;"; line 1 is empty.
$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir | Out-Null
$unit = Join-Path $srcDir 'Hx.pas'
$text = (@('unit Hx;', '', 'interface', '', 'type', '  TFoo = class', '  public', '    FIrst: Integer;', '  end;',
           '', 'implementation', '', 'procedure Use; var Foo: TFoo; begin', '  Foo.FIrst:= 1;', 'end;', '', 'end.', '') -join "`r`n")
[IO.File]::WriteAllText($unit, $text, [Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'hx.sqlite'
& $Exe index $srcDir --db $db 2>&1 | Out-Null
Check 'built the fixture index' (Test-Path $db)
$uri = Uri $unit
$didOpen = Frame ('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"' + $uri + '","languageId":"pascal","version":1,"text":' + ($text | ConvertTo-Json) + '}}}')
function HoverReq([int]$line, [int]$ch) {
  return Frame ('{"jsonrpc":"2.0","id":7,"method":"textDocument/hover","params":{"textDocument":{"uri":"' + $uri + '"},"position":{"line":' + $line + ',"character":' + $ch + '}}}')
}
$fieldReq = [byte[]]($didOpen + (HoverReq 13 8))   # "  Foo.FI|rst:= 1;"
$emptyReq = [byte[]]($didOpen + (HoverReq 1 0))    # the empty line 1
$script:ScriptN = 0
function Script([string]$result, [int]$delay = 0) {
  $script:ScriptN++
  $f = Join-Path $WorkDir "script$($script:ScriptN).tsv"
  [IO.File]::WriteAllText($f, "textDocument/hover`t$delay`t$result`r`n", [Text.Encoding]::ASCII)
  return @{ DRAGLINT_STUB_SCRIPT = $f }
}
$plainArgs = @('lsp', '--proxy', '--delphi-lsp', $stub)
$offArgs   = @('lsp', '--proxy', '--db', $db, '--merge-budget-ms', '20000', '--delphi-lsp', $stub)
$onArgs    = @('lsp', '--proxy', '--merge-hover', '--db', $db, '--merge-budget-ms', '20000', '--delphi-lsp', $stub)
$tightArgs = @('lsp', '--proxy', '--merge-hover', '--db', $db, '--merge-budget-ms', '10', '--delphi-lsp', $stub)
$Sep = "`n`n---`n`n"

# --- 3 (16a) first: it captures drag-lint's own text ---------------------------
Write-Host ''
Write-Host '(3, criterion 16a) theirs null + ours: ours alone as MarkupContent' -ForegroundColor Cyan
$r3 = Invoke-Raw $Exe $onArgs $fieldReq (Script 'null')
$m3 = Reply7 $r3.Out
$ours = if ($m3) { $m3.Value } else { $null }
Check 'reply for id 7 present' ($null -ne $m3) ''
Check 'kind is markdown and the value names FIrst' ($m3 -and $m3.Kind -eq 'markdown' -and "$ours" -match 'FIrst') ("value=$(Show $ours)")
Check 'no separator: ours alone' ("$ours" -ne '' -and -not "$ours".StartsWith('---') -and -not "$ours".Contains($Sep)) ''
Check 'Content-Length is exact' ($m3 -and $m3.Frame.Declared -eq $m3.Frame.Actual -and $m3.Frame.Declared -eq [Text.Encoding]::UTF8.GetByteCount($m3.Frame.Body)) ''
if ("$ours" -eq '') { $ours = '<no drag-lint hover captured>' }

# --- 1 (15) both -----------------------------------------------------------------
Write-Host ''
Write-Host '(1, criterion 15) theirs MarkupContent + ours: theirs, separator, ours; range kept' -ForegroundColor Cyan
$theirs1 = '{"contents":{"kind":"markdown","value":"THEIRS-MD"},"range":{"start":{"line":13,"character":6},"end":{"line":13,"character":11}}}'
$env1 = Script $theirs1
$r1 = Invoke-Raw $Exe $onArgs $fieldReq $env1
$p1 = Invoke-Raw $Exe $plainArgs $fieldReq $env1
$m1 = Reply7 $r1.Out
Check 'value = theirs + separator + ours, exactly' ($m1 -and $m1.Kind -eq 'markdown' -and $m1.Value -eq ('THEIRS-MD' + $Sep + $ours)) ("value=$(Show $m1.Value)")
Check 'range kept' ($m1 -and $m1.Result['range'] -and $m1.Result['range']['start']['character'] -eq 6) ''

# --- 2 MarkedString shapes -------------------------------------------------------------
Write-Host ''
Write-Host '(2) theirs MarkedString (string / {language,value} / array): normalised to markdown first' -ForegroundColor Cyan
$shapes = @(
  @{ N = 'string';  R = '{"contents":"THEIRS-STR"}';                                    W = 'THEIRS-STR' },
  @{ N = 'object';  R = '{"contents":{"language":"pascal","value":"var X: Integer"}}';  W = "``````pascal`nvar X: Integer`n``````" },
  @{ N = 'array';   R = '{"contents":["A-PART",{"language":"pascal","value":"B-PART"}]}'; W = "A-PART`n`n``````pascal`nB-PART`n``````" }
)
foreach ($sh in $shapes) {
  $r2 = Invoke-Raw $Exe $onArgs $fieldReq (Script $sh.R)
  $m2 = Reply7 $r2.Out
  Check "MarkedString $($sh.N): MarkupContent markdown = normalised theirs + separator + ours" ($m2 -and $m2.Kind -eq 'markdown' -and $m2.Value -eq ($sh.W + $Sep + $ours)) ("value=$(Show $m2.Value)")
}

# --- 4 (16b) neither -------------------------------------------------------------------
Write-Host ''
Write-Host '(4, criterion 16b) neither: null forwarded byte-identical' -ForegroundColor Cyan
$env4 = Script 'null'
$r4 = Invoke-Raw $Exe $onArgs    $emptyReq $env4
$p4 = Invoke-Raw $Exe $plainArgs $emptyReq $env4
$m4 = Reply7 $r4.Out
Check 'neither: ON = plain relay' (Same $r4.Out $p4.Out) ("on=$($r4.Out.Length) plain=$($p4.Out.Length)")
Check 'neither: the result is null' ($m4 -and $m4.IsNull) ''

# --- 5 ours empty, theirs present ---------------------------------------------------------
Write-Host ''
Write-Host '(5) ours empty, theirs present: byte-identical' -ForegroundColor Cyan
$env5 = Script $theirs1
$r5 = Invoke-Raw $Exe $onArgs    $emptyReq $env5
$p5 = Invoke-Raw $Exe $plainArgs $emptyReq $env5
Check 'ours empty: ON = plain relay' (Same $r5.Out $p5.Out) ("on=$($r5.Out.Length) plain=$($p5.Out.Length)")

# --- 6 OFF vs ON -----------------------------------------------------------------------------
Write-Host ''
Write-Host '(6) OFF is the plain relay; ON differs' -ForegroundColor Cyan
$r6 = Invoke-Raw $Exe $offArgs $fieldReq $env1
Check 'OFF (--db, no --merge-hover) = plain relay, byte for byte' (Same $r6.Out $p1.Out) ("off=$($r6.Out.Length) plain=$($p1.Out.Length)")
Check 'ON differs from the plain relay (positive control)' ($r1.Out.Length -gt 0 -and -not (Same $r1.Out $p1.Out)) ("on=$($r1.Out.Length) plain=$($p1.Out.Length)")

# --- 7 budget ----------------------------------------------------------------------------------
Write-Host ''
Write-Host '(7) stub delay 200 ms, --merge-budget-ms 10: theirs byte-identical' -ForegroundColor Cyan
$env7 = Script $theirs1 200
$r7 = Invoke-Raw $Exe $tightArgs $fieldReq $env7
$p7 = Invoke-Raw $Exe $plainArgs $fieldReq $env7
Check 'over budget: ON = plain relay' (Same $r7.Out $p7.Out) ("on=$($r7.Out.Length) plain=$($p7.Out.Length)")
Check 'it was the budget that declined (stderr names it)' ((Utf8 $r7.Err) -match 'merge-hover over its 10 ms budget') ("err=$(Utf8 $r7.Err)")

# --- 8 no position (A4 fix M2) -------------------------------------------------------------------
Write-Host ''
Write-Host '(8) hover requests with no position fields: relayed untouched, no stderr line' -ForegroundColor Cyan
function NoPosHover([int]$id) {
  return Frame ('{"jsonrpc":"2.0","id":' + $id + ',"method":"textDocument/hover","params":{"textDocument":{"uri":"' + $uri + '"},"position":{}}}')
}
$in8 = [byte[]]((NoPosHover 5) + (NoPosHover 6) + $fieldReq)
$r8  = Invoke-Raw $Exe $onArgs $in8 (Script $theirs1)
$e8  = @((Utf8 $r8.Err) -split "\r?\n" | Where-Object { $_ -match 'merge-hover' })
Check 'two position-less hovers: no merge-hover stderr line' ($e8.Count -eq 0) ("lines=$($e8.Count) err=$(Utf8 $r8.Err)")
$m8 = Reply7 $r8.Out
Check 'positive control: the later hover 7 in the same session still merges' ($m8 -and $m8.Value -eq ('THEIRS-MD' + $Sep + $ours)) ("value=$(Show $m8.Value)")
$n8 = @(Split-Frames $r8.Out | ForEach-Object { try { $_.Body | ConvertFrom-Json -AsHashtable } catch { $null } } |
        Where-Object { $_ -and $_.ContainsKey('id') -and ($_['id'] -in 5, 6) -and $_.ContainsKey('result') -and $_['result']['contents']['value'] -eq 'THEIRS-MD' })
Check 'both position-less hovers got DelphiLSP''s reply, unmerged' ($n8.Count -eq 2) ("n=$($n8.Count)")

# --- 9 queue overflow (A4 fix M3) ------------------------------------------------------------------
Write-Host ''
Write-Host '(9) 56 hovers against a queue of 8: an overflowed reply does not wait out the budget' -ForegroundColor Cyan
$many = [byte[]]$didOpen
foreach ($id in 101..156) {
  $many += Frame ('{"jsonrpc":"2.0","id":' + $id + ',"method":"textDocument/hover","params":{"textDocument":{"uri":"' + $uri + '"},"position":{"line":13,"character":8}}}')
}
$qArgs = @('lsp', '--proxy', '--merge-hover', '--db', $db, '--merge-budget-ms', '4000', '--delphi-lsp', $stub)
$r9 = Invoke-Raw $Exe $qArgs $many (Script $theirs1)
$rep9 = @(Split-Frames $r9.Out | ForEach-Object { try { $_.Body | ConvertFrom-Json -AsHashtable } catch { $null } } |
          Where-Object { $_ -and $_.ContainsKey('id') -and ($_['id'] -ge 101) -and $_.ContainsKey('result') })
$unmerged = @($rep9 | Where-Object { $_['result']['contents']['value'] -eq 'THEIRS-MD' }).Count
Check 'all 56 hovers answered' ($rep9.Count -eq 56) ("n=$($rep9.Count)")
Check 'positive control: some hovers merged' (($rep9.Count - $unmerged) -gt 0) ("merged=$($rep9.Count - $unmerged)")
Check 'no over-budget line (an overflowed request no longer waits for an answer nobody computes)' (-not ((Utf8 $r9.Err) -match 'merge-hover over its')) ("unmerged=$unmerged err=$(Utf8 $r9.Err)")
Check 'positive control: the queue DID overflow (some replies unmerged)' ($unmerged -gt 0) ("unmerged=$unmerged")

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\draglint_lspproxy_mergehover_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
