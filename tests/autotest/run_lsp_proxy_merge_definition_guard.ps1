# dl:serial: LSP proxy family. Spawns and reaps LspStub children; the sibling
#   proxy guards were observed interfering with each other even when strictly
#   serialised (root cause fixed in 41b0004), so this one joins the quarantine.
<#
  run_lsp_proxy_merge_definition_guard.ps1 -- `lsp --proxy --merge-definition`
  (merge plan A5): drag-lint's definition when DelphiLSP has none, and
  textDocument/references + workspace/symbol answered by the proxy itself,
  because DelphiLSP advertises neither.

  Both sides are scripted: the P0 stub answers from a script and logs every
  frame it receives (DRAGLINT_STUB_LOG); drag-lint answers from a fixture index
  passed with --db. The caret sits MID-WORD on the field FIrst (line 13), whose
  declaration is line 7.

  Contract pinned here:
    definition [] / null      -> replaced by drag-lint's Location[] (line 7);
    definition non-empty      -> forwarded byte-identical (theirs wins);
    initialize, no providers  -> result.capabilities gains referencesProvider
                                 and workspaceSymbolProvider (true); every
                                 other capability kept;
    initialize, both present  -> byte-identical;
    references / symbol       -> answered by the proxy with drag-lint's
                                 result and NOT forwarded (absent from the
                                 stub log; positive control: a hover sent
                                 right after it IS in the log);
    references when DelphiLSP -> forwarded (in the stub log), sequenced: the
      advertised it              initialize reply is relayed first;
    OFF                       -> plain relay; ON differs.

  The proxy guards default -Exe to dll-win64; a lane passes its own engine.
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_lspproxy_mergedef_$PID"
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

# Writes $c1, then (after $gapMs) $c2, then closes stdin.
function Invoke-Raw {
  param([string]$exe, [string[]]$argv, [byte[]]$c1, [hashtable]$envs = @{}, [byte[]]$c2 = $null, [int]$gapMs = 0)
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
    if ($c2 -and $c2.Length) {
      if ($gapMs -gt 0) { Start-Sleep -Milliseconds $gapMs }
      $sin.Write($c2, 0, $c2.Length); $sin.Flush()
    }
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
# The reply for request $id: Frame, Json (hashtable), HasResult.
function ReplyOf([byte[]]$b, [int]$id) {
  foreach ($f in (Split-Frames $b)) {
    try { $j = $f.Body | ConvertFrom-Json -AsHashtable } catch { continue }
    if ($j -and $j.ContainsKey('id') -and ($j['id'] -eq $id) -and -not $j.ContainsKey('method')) {
      return [pscustomobject]@{ Frame = $f; Json = $j; HasResult = $j.ContainsKey('result') }
    }
  }
  return $null
}
function CountReplies([byte[]]$b, [int]$id) {
  $n = 0
  foreach ($f in (Split-Frames $b)) {
    try { $j = $f.Body | ConvertFrom-Json -AsHashtable } catch { continue }
    if ($j -and $j.ContainsKey('id') -and ($j['id'] -eq $id) -and -not $j.ContainsKey('method')) { $n++ }
  }
  return $n
}
# True when $res is an array holding a Location in Hx.pas starting on $line.
function HasLoc($res, [int]$line) {
  if (-not ($res -is [System.Collections.IList])) { return $false }
  foreach ($l in $res) {
    $loc = if ($l -is [System.Collections.IDictionary] -and $l.ContainsKey('location')) { $l['location'] } else { $l }
    if (($loc -is [System.Collections.IDictionary]) -and ("$($loc['uri'])" -match '(?i)hx\.pas$') -and
        ($loc['range']['start']['line'] -eq $line)) { return $true }
  }
  return $false
}
function Uri([string]$path) { return 'file:///' + ($path -replace '\\', '/') }
function LogHas([string]$log, [string]$method) {
  if (-not (Test-Path $log)) { return $false }
  return [bool](Get-Content $log | Where-Object { $_.Split("`t")[0] -eq $method })
}

Write-Host ''
Write-Host 'run_lsp_proxy_merge_definition_guard -- definition fallback + references / workspace-symbol (A5)' -ForegroundColor Cyan

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
# Line 7 (0-based) declares "    FIrst: Integer;"; line 13 is "  Foo.FIrst:= 1;".
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
$initReq = Frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
function PosReq([int]$id, [string]$method, [string]$extra = '') {
  return Frame ('{"jsonrpc":"2.0","id":' + $id + ',"method":"' + $method + '","params":{"textDocument":{"uri":"' + $uri + '"},"position":{"line":13,"character":8}' + $extra + '}}')
}
$defReq   = [byte[]]($didOpen + (PosReq 7 'textDocument/definition'))
$refReq   = PosReq 9 'textDocument/references' ',"context":{"includeDeclaration":true}'
$symReq   = Frame '{"jsonrpc":"2.0","id":11,"method":"workspace/symbol","params":{"query":"TFoo"}}'
$hoverReq = PosReq 10 'textDocument/hover'
$script:ScriptN = 0
# $lines: array of @(method, delay, result)
function Script([object[]]$lines) {
  $script:ScriptN++
  $f   = Join-Path $WorkDir "script$($script:ScriptN).tsv"
  $log = Join-Path $WorkDir "stub$($script:ScriptN).log"
  $body = ($lines | ForEach-Object { "$($_[0])`t$($_[1])`t$($_[2])" }) -join "`r`n"
  [IO.File]::WriteAllText($f, $body + "`r`n", [Text.Encoding]::ASCII)
  return @{ DRAGLINT_STUB_SCRIPT = $f; DRAGLINT_STUB_LOG = $log }
}
$plainArgs = @('lsp', '--proxy', '--delphi-lsp', $stub)
$offArgs   = @('lsp', '--proxy', '--db', $db, '--merge-budget-ms', '20000', '--delphi-lsp', $stub)
$onArgs    = @('lsp', '--proxy', '--merge-definition', '--db', $db, '--merge-budget-ms', '20000', '--delphi-lsp', $stub)
$theirsDef = '[{"uri":"file:///C:/elsewhere/Other.pas","range":{"start":{"line":3,"character":2},"end":{"line":3,"character":7}}}]'
$initNone  = '{"capabilities":{"hoverProvider":true,"definitionProvider":true}}'
$initBoth  = '{"capabilities":{"hoverProvider":true,"referencesProvider":true,"workspaceSymbolProvider":true}}'

# --- 1 definition [] / null -> ours ------------------------------------------------
Write-Host ''
Write-Host '(1) DelphiLSP definition [] or null: replaced by drag-lint''s Location[]' -ForegroundColor Cyan
foreach ($theirs in @('[]', 'null')) {
  $env1 = Script @(,@('textDocument/definition', 0, $theirs))
  $r1 = Invoke-Raw $Exe $onArgs $defReq $env1
  $m1 = ReplyOf $r1.Out 7
  Check "theirs $($theirs): reply carries drag-lint's declaration of FIrst (Hx.pas line 7)" ($m1 -and (HasLoc $m1.Json['result'] 7)) ("body=$(if ($m1) { $m1.Frame.Body } else { '<none>' })")
  Check "theirs $($theirs): Content-Length is exact" ($m1 -and $m1.Frame.Declared -eq [Text.Encoding]::UTF8.GetByteCount($m1.Frame.Body)) ''
}

# --- 2 definition non-empty -> theirs, byte-identical -------------------------------
Write-Host ''
Write-Host '(2) DelphiLSP definition non-empty: forwarded byte-identical' -ForegroundColor Cyan
$env2 = Script @(,@('textDocument/definition', 0, $theirsDef))
$r2 = Invoke-Raw $Exe $onArgs    $defReq $env2
$p2 = Invoke-Raw $Exe $plainArgs $defReq $env2
Check 'theirs non-empty: ON = plain relay, byte for byte' (Same $r2.Out $p2.Out) ("on=$($r2.Out.Length) plain=$($p2.Out.Length)")

# --- 3 initialize gains the providers ------------------------------------------------
Write-Host ''
Write-Host '(3) initialize without referencesProvider / workspaceSymbolProvider: both added' -ForegroundColor Cyan
$env3 = Script @(,@('initialize', 0, $initNone))
$r3 = Invoke-Raw $Exe $onArgs $initReq $env3
$m3 = ReplyOf $r3.Out 1
$cap3 = if ($m3 -and $m3.HasResult) { $m3.Json['result']['capabilities'] } else { $null }
Check 'referencesProvider added (true)' ($cap3 -and $cap3['referencesProvider'] -eq $true) ("body=$(if ($m3) { $m3.Frame.Body } else { '<none>' })")
Check 'workspaceSymbolProvider added (true)' ($cap3 -and $cap3['workspaceSymbolProvider'] -eq $true) ''
Check 'DelphiLSP''s own capabilities kept' ($cap3 -and $cap3['hoverProvider'] -eq $true -and $cap3['definitionProvider'] -eq $true) ''

# --- 4 initialize that already has both -> byte-identical --------------------------
Write-Host ''
Write-Host '(4) initialize that already advertises both: byte-identical' -ForegroundColor Cyan
$env4 = Script @(,@('initialize', 0, $initBoth))
$r4 = Invoke-Raw $Exe $onArgs    $initReq $env4
$p4 = Invoke-Raw $Exe $plainArgs $initReq $env4
Check 'both present: ON = plain relay, byte for byte' (Same $r4.Out $p4.Out) ("on=$($r4.Out.Length) plain=$($p4.Out.Length)")

# --- 5 references / workspace symbol answered by the proxy ------------------------
Write-Host ''
Write-Host '(5) references + workspace/symbol answered by the proxy, not forwarded' -ForegroundColor Cyan
$c5 = [byte[]]($initReq + $didOpen + $refReq + $symReq + $hoverReq)
$env5 = Script @(@('initialize', 0, $initNone), @('textDocument/hover', 300, 'null'))
$r5 = Invoke-Raw $Exe $onArgs $c5 $env5
$m9  = ReplyOf $r5.Out 9
$m11 = ReplyOf $r5.Out 11
Check 'references reply carries the use on line 13' ($m9 -and $m9.HasResult -and (HasLoc $m9.Json['result'] 13)) ("body=$(if ($m9) { $m9.Frame.Body } else { '<none>' })")
Check 'references includeDeclaration: the declaration on line 7 too' ($m9 -and $m9.HasResult -and (HasLoc $m9.Json['result'] 7)) ''
Check 'exactly one reply for id 9' ((CountReplies $r5.Out 9) -eq 1) ''
Check 'workspace/symbol reply names TFoo' ($m11 -and $m11.HasResult -and (@($m11.Json['result'] | Where-Object { $_['name'] -eq 'TFoo' }).Count -ge 1)) ("body=$(if ($m11) { $m11.Frame.Body } else { '<none>' })")
Check 'references ABSENT from the stub log' (-not (LogHas $env5.DRAGLINT_STUB_LOG 'textDocument/references')) ''
Check 'workspace/symbol ABSENT from the stub log' (-not (LogHas $env5.DRAGLINT_STUB_LOG 'workspace/symbol')) ''
Check 'positive control: the hover sent after them IS in the stub log' (LogHas $env5.DRAGLINT_STUB_LOG 'textDocument/hover') ''
$p5 = Invoke-Raw $Exe $plainArgs $c5 (Script @(@('initialize', 0, $initNone), @('textDocument/hover', 300, 'null')))
Check 'positive control: the plain relay DOES forward references' (LogHas "$WorkDir\stub$($script:ScriptN).log" 'textDocument/references') ''

# --- 6 references when DelphiLSP advertised it: forwarded ---------------------------
Write-Host ''
Write-Host '(6) DelphiLSP advertised referencesProvider: references forwarded (theirs wins)' -ForegroundColor Cyan
$env6 = Script @(,@('initialize', 0, $initBoth))
$r6 = Invoke-Raw $Exe $onArgs ([byte[]]($initReq + $didOpen)) $env6 $refReq 1500
Check 'references IS in the stub log' (LogHas $env6.DRAGLINT_STUB_LOG 'textDocument/references') ''
$m6 = ReplyOf $r6.Out 9
Check 'the reply for id 9 is DelphiLSP''s (error: not scripted)' ($m6 -and -not $m6.HasResult -and $m6.Json.ContainsKey('error')) ("body=$(if ($m6) { $m6.Frame.Body } else { '<none>' })")

# --- 7 OFF vs ON ------------------------------------------------------------------
Write-Host ''
Write-Host '(7) OFF is the plain relay; ON differs' -ForegroundColor Cyan
$env7 = Script @(,@('textDocument/definition', 0, '[]'))
$r7on  = Invoke-Raw $Exe $onArgs    $defReq $env7
$r7off = Invoke-Raw $Exe $offArgs   $defReq $env7
$p7    = Invoke-Raw $Exe $plainArgs $defReq $env7
Check 'OFF (--db, no --merge-definition) = plain relay, byte for byte' (Same $r7off.Out $p7.Out) ("off=$($r7off.Out.Length) plain=$($p7.Out.Length)")
Check 'ON differs from the plain relay (positive control)' ($r7on.Out.Length -gt 0 -and -not (Same $r7on.Out $p7.Out)) ("on=$($r7on.Out.Length) plain=$($p7.Out.Length) err=$(Utf8 $r7on.Err)")

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\draglint_lspproxy_mergedef_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
