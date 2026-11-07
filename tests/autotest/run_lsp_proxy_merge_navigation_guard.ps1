#Requires -Version 7
# dl:serial: LSP proxy family. Spawns and reaps LspStub children, as its siblings do.
<#
  run_lsp_proxy_merge_navigation_guard.ps1 -- `lsp --proxy --merge-navigation`
  (L-PROXY-HIERARCHY): the type and call hierarchy, typeDefinition, documentHighlight
  and foldingRange answered by the proxy for every provider DelphiLSP does not advertise.

  Both sides are scripted: the P0 stub answers from a script and logs every frame it
  receives (DRAGLINT_STUB_LOG); drag-lint answers from a fixture index passed with --db.

  Contract pinned here:
    initialize, no providers   -> the five providers added (true); DelphiLSP's own kept;
                                  references / workspace symbol NOT added (their flag is off);
    initialize, all five       -> byte-identical to the plain relay;
    a provider it advertises   -> that provider stays: its requests are forwarded, the
                                  others are still answered here;
    each of the nine requests  -> one reply, NOT forwarded (absent from the stub log; positive
                                  control: the hover sent after them IS logged), the SAME result
                                  plain `lsp --db` gives (a handler answering [] fails it);
    nothing on stdout but the  -> no reply with the capture's internal id 0;
      replies
    $/cancelRequest            -> for an answered id: dropped; for a forwarded id: forwarded;
    flag off                   -> plain relay forwards them all;
    --merge-definition alone   -> no navigation provider added, requests forwarded;
    no index                   -> one reply, [].

  The proxy guards default -Exe to dll-win64; a lane passes its own engine.
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_lspproxy_mergenav_$PID"
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
. (Join-Path $PSScriptRoot 'lib\EngineCompanions.ps1')
[void](Initialize-EngineCompanions -Exe $Exe)
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

# Writes each frame of $c1, waiting after a request for its reply: the engine's job queue holds
# eight (QUEUE_MAX, over it a request is answered [] by design), so a burst would measure that.
function Invoke-Raw {
  param([string]$exe, [string[]]$argv, [byte[][]]$c1, [hashtable]$envs = @{})
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
    foreach ($fr in $c1) {
      $sin.Write($fr, 0, $fr.Length); $sin.Flush()
      $mId = [regex]::Match([Text.Encoding]::UTF8.GetString($fr), '"id":(\d+),"method"')
      if (-not $mId.Success) { continue }
      $until = (Get-Date).AddSeconds(30)
      while ((Get-Date) -lt $until -and -not $p.HasExited) {
        if ([Text.Encoding]::UTF8.GetString($outMs.ToArray()) -match ('"id"\s*:\s*' + $mId.Groups[1].Value + '\s*[,}]')) { break }
        Start-Sleep -Milliseconds 20
      }
    }
    $sin.Close()
  } catch { }
  $done = $p.WaitForExit(60000)
  if (-not $done) { try { $p.Kill($true) } catch { } }
  [void]$outT.Wait(5000); [void]$errT.Wait(5000)
  $code = if ($done) { $p.ExitCode } else { -999 }
  return [pscustomobject]@{ Out = $outMs.ToArray(); Err = $errMs.ToArray(); Code = $code }
}
function FrameOf([string]$body) {
  $bb = [Text.Encoding]::UTF8.GetBytes($body)
  $h  = [Text.Encoding]::ASCII.GetBytes("Content-Length: $($bb.Length)`r`n`r`n")
  return [byte[]]($h + $bb)
}
# The proxy also forwards the index server's own notices (run_lsp_proxy_notices_guard.ps1):
# extra frames, not part of DelphiLSP's relayed bytes, so "= plain relay" compares without them.
function Strip-Notices([byte[]]$b) {
  if (-not $b) { return ,[byte[]]@() }
  $s = [Text.Encoding]::Latin1.GetString($b)
  $o = New-Object System.Text.StringBuilder
  $pos = 0
  while ($pos -lt $s.Length) {
    $m = [regex]::Match($s.Substring($pos), '(?is)\AContent-Length:\s*(\d+)[^\r]*\r\n(?:[^\r]*\r\n)*?\r\n')
    if (-not $m.Success) { [void]$o.Append($s.Substring($pos)); break }
    $end = [Math]::Min($s.Length, $pos + $m.Length + [int]$m.Groups[1].Value)
    $frame = $s.Substring($pos, $end - $pos)
    if ($frame -notmatch '"method"\s*:\s*"(draglint/context|window/showMessage)"') { [void]$o.Append($frame) }
    $pos = $end
  }
  return ,[Text.Encoding]::Latin1.GetBytes($o.ToString())
}
function Same([byte[]]$a, [byte[]]$b) {
  $a = Strip-Notices $a; $b = Strip-Notices $b
  return ($a.Length -gt 0) -and ($a.Length -eq $b.Length) -and ($null -eq (Compare-Object $a $b -SyncWindow 0))
}
function Split-Frames([byte[]]$b) {
  $res = @()
  $s = [Text.Encoding]::Latin1.GetString($b)
  $pos = 0
  while ($true) {
    $m = [regex]::Match($s.Substring($pos), '(?is)Content-Length:\s*(\d+)[^\r]*\r\n(?:[^\r]*\r\n)*?\r\n')
    if (-not $m.Success) { break }
    $start = $pos + $m.Index + $m.Length
    $decl  = [int]$m.Groups[1].Value
    $avail = [Math]::Min($decl, $b.Length - $start)
    $res  += [pscustomobject]@{ Declared = $decl; Actual = $avail; Body = [Text.Encoding]::UTF8.GetString($b, $start, $avail) }
    $pos   = $start + $avail
  }
  return ,$res
}
# Every reply for request $id: the frame, the parsed body, its raw result as compact JSON.
function RepliesOf([byte[]]$b, $id) {
  $out = @()
  foreach ($f in (Split-Frames $b)) {
    try { $j = $f.Body | ConvertFrom-Json -AsHashtable } catch { continue }
    if ($j -and $j.ContainsKey('id') -and ($j['id'] -eq $id) -and -not $j.ContainsKey('method')) {
      $out += [pscustomobject]@{ Frame = $f; Json = $j; Result = (ConvertTo-Json -InputObject $j['result'] -Compress -Depth 20) }
    }
  }
  return ,$out
}
function LogHas([string]$log, [string]$method) {
  if (-not (Test-Path $log)) { return $false }
  return [bool](Get-Content $log | Where-Object { $_.Split("`t")[0] -eq $method })
}

Write-Host ''
Write-Host 'run_lsp_proxy_merge_navigation_guard -- hierarchy, typeDefinition, highlight, folding in the proxy' -ForegroundColor Cyan

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
$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir | Out-Null
$unit = Join-Path $srcDir 'Nx.pas'
$lines = @(
  'unit Nx;', '', 'interface', '', 'type',
  '  TBase = class', '    procedure Draw;', '  end;', '',
  '  TMid = class(TBase)', '  end;', '',
  'procedure Callee;', 'procedure Caller;', '',
  'implementation', '',
  'procedure TBase.Draw;', 'begin', 'end;', '',
  'procedure Callee;', 'begin', 'end;', '',
  'procedure Caller;', 'var', '  Mid: TMid;', 'begin', '  Mid:= nil;', '  Mid.Draw;', '  Callee;', 'end;', '',
  'end.', '')
$text = $lines -join "`r`n"
[IO.File]::WriteAllText($unit, $text, [Text.Encoding]::ASCII)
function LineNo([string]$rx) { for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $rx) { return $i } } throw "no line $rx" }
$db = Join-Path $WorkDir 'nx.sqlite'
$ea = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $Exe index $srcDir --db $db 2>&1 | Out-Null
$ErrorActionPreference = $ea
Check 'built the fixture index' (Test-Path $db)
$uri = 'file:///' + ($unit -replace '\\', '/')
$lMid = LineNo '^  TMid = class'; $lBase = LineNo '^  TBase = class'; $lUseMid = LineNo '^  Mid:= nil'; $lCallee = LineNo '^procedure Callee;'
$didOpen = FrameOf ('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"' + $uri + '","languageId":"pascal","version":1,"text":' + ($text | ConvertTo-Json) + '}}}')
$initReq = FrameOf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
function ReqBody([int]$id, [string]$method, [string]$params) { return '{"jsonrpc":"2.0","id":' + $id + ',"method":"' + $method + '","params":' + $params + '}' }
function PosParams([int]$line, [int]$col) { return '{"textDocument":{"uri":"' + $uri + '"},"position":{"line":' + $line + ',"character":' + $col + '}}' }
$docParams = '{"textDocument":{"uri":"' + $uri + '"}}'
$script:ScriptN = 0
function Script([object[]]$scriptLines) {
  $script:ScriptN++
  $f   = Join-Path $WorkDir "script$($script:ScriptN).tsv"
  $log = Join-Path $WorkDir "stub$($script:ScriptN).log"
  $body = ($scriptLines | ForEach-Object { "$($_[0])`t$($_[1])`t$($_[2])" }) -join "`r`n"
  [IO.File]::WriteAllText($f, $body + "`r`n", [Text.Encoding]::ASCII)
  return @{ DRAGLINT_STUB_SCRIPT = $f; DRAGLINT_STUB_LOG = $log }
}
$plainArgs = @('lsp', '--proxy', '--delphi-lsp', $stub)
$onArgs    = @('lsp', '--proxy', '--merge-navigation', '--db', $db, '--merge-budget-ms', '20000', '--delphi-lsp', $stub)
$defArgs   = @('lsp', '--proxy', '--merge-definition', '--db', $db, '--merge-budget-ms', '20000', '--delphi-lsp', $stub)
$noDbArgs  = @('lsp', '--proxy', '--merge-navigation', '--db', (Join-Path $WorkDir 'gone.sqlite'), '--merge-budget-ms', '20000', '--delphi-lsp', $stub)
$initNone  = '{"capabilities":{"hoverProvider":true,"definitionProvider":true}}'
$initAll   = '{"capabilities":{"typeHierarchyProvider":true,"callHierarchyProvider":true,"typeDefinitionProvider":true,"documentHighlightProvider":true,"foldingRangeProvider":true}}'
$initSome  = '{"capabilities":{"typeHierarchyProvider":true,"foldingRangeProvider":{},"typeDefinitionProvider":false}}'
$NavCaps   = @('typeHierarchyProvider', 'callHierarchyProvider', 'typeDefinitionProvider', 'documentHighlightProvider', 'foldingRangeProvider')

# --- 1 initialize gains the providers -----------------------------------------------
Write-Host ''
Write-Host '(1) initialize without the providers: all five added, DelphiLSP''s own kept' -ForegroundColor Cyan
$e1 = Script @(,@('initialize', 0, $initNone))
$r1 = Invoke-Raw $Exe $onArgs @(,$initReq) $e1
$m1 = (RepliesOf $r1.Out 1)[0]
$cap1 = if ($m1) { $m1.Json['result']['capabilities'] } else { $null }
foreach ($c in $NavCaps) { Check "$c added (true)" ($cap1 -and $cap1[$c] -eq $true) ("body=$(if ($m1) { $m1.Frame.Body } else { '<none>' })") }
Check 'DelphiLSP''s own capabilities kept' ($cap1 -and $cap1['hoverProvider'] -eq $true -and $cap1['definitionProvider'] -eq $true)
Check 'referencesProvider NOT added: that is --merge-definition''s' ($cap1 -and -not $cap1.ContainsKey('referencesProvider'))
Check 'Content-Length is exact' ($m1 -and $m1.Frame.Declared -eq [Text.Encoding]::UTF8.GetByteCount($m1.Frame.Body))

# --- 2 initialize that already has all five -> byte-identical ------------------------
Write-Host ''
Write-Host '(2) initialize that advertises all five: byte-identical to the plain relay' -ForegroundColor Cyan
$e2 = Script @(,@('initialize', 0, $initAll))
$r2 = Invoke-Raw $Exe $onArgs    @(,$initReq) $e2
$p2 = Invoke-Raw $Exe $plainArgs @(,$initReq) $e2
Check 'all present: ON = plain relay, byte for byte' (Same $r2.Out $p2.Out) ("on=$($r2.Out.Length) plain=$($p2.Out.Length)")

# --- 3 every request answered here, with what plain lsp answers -----------------------
Write-Host ''
Write-Host '(3) the nine requests: answered by the proxy, not forwarded, same result as plain lsp' -ForegroundColor Cyan
$colMid = $lines[$lMid].IndexOf('TMid') + 1
$colUse = $lines[$lUseMid].IndexOf('Mid') + 1
$colCallee = $lines[$lCallee].IndexOf('Callee') + 1
# Stage one: prepare answers, whose items the follow-ups must echo.
$prep = @(
  (ReqBody 21 'textDocument/prepareTypeHierarchy' (PosParams $lMid $colMid)),
  (ReqBody 22 'textDocument/prepareCallHierarchy' (PosParams $lCallee $colCallee)))
$e3a = Script @(,@('initialize', 0, $initNone))
$frames3a = @($initReq, $didOpen)
foreach ($q in $prep) { $frames3a += ,(FrameOf $q) }
$r3a = Invoke-Raw $Exe $onArgs $frames3a $e3a
$th = (RepliesOf $r3a.Out 21)[0]
$ch = (RepliesOf $r3a.Out 22)[0]
Check 'prepareTypeHierarchy answers TMid' ($th -and $th.Json['result'] -and $th.Json['result'][0]['name'] -eq 'TMid') ("body=$(if ($th) { $th.Frame.Body } else { '<none>' })")
Check 'prepareCallHierarchy answers Callee' ($ch -and $ch.Json['result'] -and "$($ch.Json['result'][0]['name'])" -match 'Callee') ("body=$(if ($ch) { $ch.Frame.Body } else { '<none>' })")
if (-not $th -or -not $ch -or -not $th.Json['result'] -or -not $ch.Json['result']) { throw 'no prepare answer: the follow-ups cannot run' }
$thItem = $th.Json['result'][0] | ConvertTo-Json -Compress -Depth 20
$chItem = $ch.Json['result'][0] | ConvertTo-Json -Compress -Depth 20
$nine = @(
  @{ id = 21; m = 'textDocument/prepareTypeHierarchy'; p = (PosParams $lMid $colMid) },
  @{ id = 22; m = 'textDocument/prepareCallHierarchy'; p = (PosParams $lCallee $colCallee) },
  @{ id = 23; m = 'typeHierarchy/supertypes';          p = ('{"item":' + $thItem + '}') },
  @{ id = 24; m = 'typeHierarchy/subtypes';            p = ('{"item":' + $thItem + '}') },
  @{ id = 25; m = 'callHierarchy/incomingCalls';       p = ('{"item":' + $chItem + '}') },
  @{ id = 26; m = 'callHierarchy/outgoingCalls';       p = ('{"item":' + $chItem + '}') },
  @{ id = 27; m = 'textDocument/typeDefinition';       p = (PosParams $lUseMid $colUse) },
  @{ id = 28; m = 'textDocument/documentHighlight';    p = (PosParams $lUseMid $colUse) },
  @{ id = 29; m = 'textDocument/foldingRange';         p = $docParams })
$frames3 = @($initReq, $didOpen)
foreach ($q in $nine) { $frames3 += ,(FrameOf (ReqBody $q.id $q.m $q.p)) }
$frames3 += ,(FrameOf (ReqBody 30 'textDocument/hover' (PosParams $lUseMid $colUse)))
$e3 = Script @(@('initialize', 0, $initNone), @('textDocument/hover', 300, 'null'))
$r3 = Invoke-Raw $Exe $onArgs $frames3 $e3
# The same requests against plain `lsp --db`: the answer the proxy must not drift from.
$plainFrames = @($initReq, $didOpen)
foreach ($q in $nine) { $plainFrames += ,(FrameOf (ReqBody $q.id $q.m $q.p)) }
$plainFrames += ,(FrameOf '{"jsonrpc":"2.0","id":2,"method":"shutdown","params":{}}')
$lspR = Invoke-Raw $Exe @('lsp', '--db', $db) $plainFrames
foreach ($q in $nine) {
  $mine = RepliesOf $r3.Out $q.id
  $base = RepliesOf $lspR.Out $q.id
  Check "$($q.m): exactly one reply" ($mine.Count -eq 1) ("count=$($mine.Count)")
  Check "$($q.m): absent from the stub log" (-not (LogHas $e3.DRAGLINT_STUB_LOG $q.m))
  Check "$($q.m): same result as plain lsp" ($base.Count -eq 1 -and $mine.Count -eq 1 -and $mine[0].Result -eq $base[0].Result) ("proxy=$(if ($mine.Count) { $mine[0].Result } else { '<none>' }) plain=$(if ($base.Count) { $base[0].Result } else { '<none>' })")
}
function ResultOf($id) { return @((RepliesOf $r3.Out $id)[0].Json['result']) }
# Positive controls on the content: [] answered by both sides would pass the parity above.
Check 'supertypes(TMid) = [TBase]' ((@(ResultOf 23).Count -eq 1) -and (@(ResultOf 23)[0]['name'] -eq 'TBase')) ((RepliesOf $r3.Out 23)[0].Result)
Check 'subtypes(TMid) = []' (@(ResultOf 24).Count -eq 0) ((RepliesOf $r3.Out 24)[0].Result)
Check 'incomingCalls(Callee) names Caller' (((RepliesOf $r3.Out 25)[0].Result) -match 'Caller') ''
Check 'typeDefinition(Mid) lands on TMid''s line' (@(ResultOf 27)[0]['range']['start']['line'] -eq $lMid) ''
Check 'documentHighlight(Mid) has several occurrences' (@(ResultOf 28).Count -ge 2) ''
Check 'foldingRange is not empty' (@(ResultOf 29).Count -ge 1) ''
Check 'nothing leaked from the capture: no reply with id 0' ((RepliesOf $r3.Out 0).Count -eq 0) ''
Check 'positive control: the hover sent after them IS in the stub log' (LogHas $e3.DRAGLINT_STUB_LOG 'textDocument/hover')
$eP = Script @(@('initialize', 0, $initNone), @('textDocument/hover', 300, 'null'))
$null = Invoke-Raw $Exe $plainArgs $frames3 $eP
Check 'positive control: the plain relay DOES forward them' ((LogHas $eP.DRAGLINT_STUB_LOG 'textDocument/foldingRange') -and (LogHas $eP.DRAGLINT_STUB_LOG 'typeHierarchy/subtypes'))

# --- 4 a provider DelphiLSP advertises stays its own ---------------------------------
Write-Host ''
Write-Host '(4) partly advertised: those stay DelphiLSP''s (false counts as not advertised)' -ForegroundColor Cyan
$foldTheirs = '[{"startLine":1,"endLine":2}]'
$frames4 = @($initReq, $didOpen, (FrameOf (ReqBody 41 'textDocument/foldingRange' $docParams)),
             (FrameOf (ReqBody 42 'textDocument/typeDefinition' (PosParams $lUseMid $colUse))),
             (FrameOf (ReqBody 43 'textDocument/prepareTypeHierarchy' (PosParams $lMid $colMid))),
             (FrameOf (ReqBody 44 'textDocument/documentHighlight' (PosParams $lUseMid $colUse))))
$e4 = Script @(@('initialize', 0, $initSome), @('textDocument/foldingRange', 0, $foldTheirs), @('textDocument/prepareTypeHierarchy', 0, 'null'))
# The frames after initialize arrive after its reply (Invoke-Raw waits): that is where the proxy learns.
$o4 = (Invoke-Raw $Exe $onArgs $frames4 $e4).Out
$m41 = (RepliesOf $o4 1)[0]
$cap4 = if ($m41) { $m41.Json['result']['capabilities'] } else { $null }
Check 'an options object ({}) is advertised: kept' ($cap4 -and $cap4['foldingRangeProvider'] -is [System.Collections.IDictionary]) ("body=$(if ($m41) { $m41.Frame.Body } else { '<none>' })")
Check 'typeDefinitionProvider false: replaced by true' ($cap4 -and $cap4['typeDefinitionProvider'] -eq $true)
Check 'callHierarchyProvider absent: added' ($cap4 -and $cap4['callHierarchyProvider'] -eq $true)
Check 'foldingRange forwarded: DelphiLSP''s reply comes back' ((LogHas $e4.DRAGLINT_STUB_LOG 'textDocument/foldingRange') -and ((RepliesOf $o4 41)[0].Result -match '"startLine":1'))
Check 'prepareTypeHierarchy forwarded (a follow-up shares its provider)' (LogHas $e4.DRAGLINT_STUB_LOG 'textDocument/prepareTypeHierarchy')
Check 'typeDefinition answered here (false was not advertised)' ((-not (LogHas $e4.DRAGLINT_STUB_LOG 'textDocument/typeDefinition')) -and ((RepliesOf $o4 42).Count -eq 1))
Check 'documentHighlight answered here' ((-not (LogHas $e4.DRAGLINT_STUB_LOG 'textDocument/documentHighlight')) -and ((RepliesOf $o4 44).Count -eq 1))

# --- 5 $/cancelRequest -------------------------------------------------------------
Write-Host ''
Write-Host '(5) $/cancelRequest: dropped for an answered id, forwarded for a forwarded one' -ForegroundColor Cyan
$frames5 = @($initReq, $didOpen, (FrameOf (ReqBody 51 'textDocument/foldingRange' $docParams)),
             (FrameOf '{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":51}}'),
             (FrameOf (ReqBody 52 'textDocument/hover' (PosParams $lUseMid $colUse))),
             (FrameOf '{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":52}}'))
$e5 = Script @(@('initialize', 0, $initNone), @('textDocument/hover', 300, 'null'))
$r5 = Invoke-Raw $Exe $onArgs $frames5 $e5
$n5 = @(Get-Content $e5.DRAGLINT_STUB_LOG | Where-Object { $_.Split("`t")[0] -eq '$/cancelRequest' }).Count
Check 'exactly ONE $/cancelRequest reached DelphiLSP' ($n5 -eq 1) "cancels=$n5"
Check 'foldingRange id 51 still answered exactly once' ((RepliesOf $r5.Out 51).Count -eq 1)

# --- 6 the flag is its own -----------------------------------------------------------
Write-Host ''
Write-Host '(6) --merge-definition alone: no navigation provider, requests forwarded' -ForegroundColor Cyan
$frames6 = @($initReq, $didOpen, (FrameOf (ReqBody 61 'textDocument/foldingRange' $docParams)), (FrameOf (ReqBody 62 'textDocument/hover' (PosParams $lUseMid $colUse))))
$e6 = Script @(@('initialize', 0, $initNone), @('textDocument/foldingRange', 0, '[]'), @('textDocument/hover', 300, 'null'))
$r6 = Invoke-Raw $Exe $defArgs $frames6 $e6
$cap6 = (RepliesOf $r6.Out 1)[0].Json['result']['capabilities']
Check 'foldingRangeProvider NOT added' (-not $cap6.ContainsKey('foldingRangeProvider'))
Check 'referencesProvider still added: its own contract' ($cap6['referencesProvider'] -eq $true)
Check 'foldingRange forwarded' (LogHas $e6.DRAGLINT_STUB_LOG 'textDocument/foldingRange')

# --- 7 no index: one reply, [] -------------------------------------------------------
Write-Host ''
Write-Host '(7) no index: exactly one reply, []' -ForegroundColor Cyan
$frames7 = @($initReq, $didOpen, (FrameOf (ReqBody 71 'textDocument/typeDefinition' (PosParams $lUseMid $colUse))))
$e7 = Script @(,@('initialize', 0, $initNone))
$r7 = Invoke-Raw $Exe $noDbArgs $frames7 $e7
$m7 = RepliesOf $r7.Out 71
Check 'typeDefinition answered once with []' ($m7.Count -eq 1 -and $m7[0].Frame.Body -match '"result":\[\]') ("body=$(if ($m7.Count) { $m7[0].Frame.Body } else { '<none>' })")
Check 'and not forwarded' (-not (LogHas $e7.DRAGLINT_STUB_LOG 'textDocument/typeDefinition'))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
