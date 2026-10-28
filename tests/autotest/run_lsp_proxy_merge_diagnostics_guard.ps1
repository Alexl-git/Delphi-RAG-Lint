#Requires -Version 7
# dl:serial: LSP proxy family. Spawns and reaps LspStub children; the sibling
#   proxy guards were observed interfering with each other even when strictly
#   serialised (root cause fixed in 41b0004), so this one joins the quarantine.
<#
  run_lsp_proxy_merge_diagnostics_guard.ps1 -- `lsp --proxy --merge-diagnostics`
  appends drag-lint's findings to DelphiLSP's OWN publishDiagnostics frame
  (merge plan A1; spec criteria 17, 18, 4, 19).

  WHY ONE FRAME. publishDiagnostics REPLACES the client's diagnostic set for the
  URI, and the IDE sees the proxy as one server: a separate drag-lint frame
  would erase DelphiLSP's compiler errors and be erased by the next one. So the
  only stable merge is to rewrite the child's frame in flight.

  Positive controls. The dirty fixture provably trips a rule (`lint --json`
  returns >= 1 finding) and the clean one provably does not; every byte-
  identity case is paired with a case where the SAME engine does rewrite (a),
  so a proxy that never merges fails the guard instead of passing it.

  Checks:
    (a) ON, dirty fixture: ONE publishDiagnostics frame carrying BOTH the stub's
        diagnostic (source delphilsp-stub) and a source drag-lint diagnostic;
    (b) ON, clean fixture: the child's frame is forwarded byte-identical;
    (c) FAIL OPEN: a body that contains the method name but is not JSON is
        forwarded byte-identical, and exactly one stderr line names the merge;
    (d) --merge-budget-ms 0: byte-identical (the budget leg of fail-open);
    (e) OFF (budget flag only) is byte-identical to the plain relay and to the
        pushed bytes; ON differs -- the divergence IS the positive control;
    (f) a scripted completion reply relays byte-identical with merge ON;
    (g) DIRTY: after didChange the next publish is byte-identical; after
        didChange + didSave it is merged (the pair is the control);
    (h) a stub message containing U+00FC: the merged frame's Content-Length is
        the UTF-8 byte length of its body and the message survives intact.

  The proxy guards default -Exe to dll-win64; a lane passes its own engine.
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_lspproxy_mergediag_$PID"
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
  param([string]$exe, [string[]]$argv, [byte[]]$c1, [hashtable]$envs = @{}, [byte[]]$c2 = $null, [int]$delayMs = 0)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName               = $exe
  foreach ($a in $argv) { [void]$psi.ArgumentList.Add($a) }
  foreach ($k in $envs.Keys) { $psi.Environment[$k] = $envs[$k] }
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
    if ($c2 -and $c2.Length) { Start-Sleep -Milliseconds $delayMs; $sin.Write($c2, 0, $c2.Length); $sin.Flush() }
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
# Splits a byte stream into LSP frames (raw non-frame bytes such as the stub's
# preamble are skipped). Each item: Declared, Actual, Body.
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
# The publishDiagnostics frames of an output stream, parsed.
function Publishes([byte[]]$b) {
  $res = @()
  foreach ($f in (Split-Frames $b)) {
    try { $j = $f.Body | ConvertFrom-Json -AsHashtable } catch { continue }
    if ($j -and ($j['method'] -eq 'textDocument/publishDiagnostics')) {
      $res += [pscustomobject]@{ Frame = $f; Json = $j; Sources = @($j['params']['diagnostics'] | ForEach-Object { $_['source'] }) }
    }
  }
  return ,$res
}
function Uri([string]$path) { return 'file:///' + ($path -replace '\\', '/') }
function PublishBody([string]$uri, [string]$message) {
  return '{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"' + $uri +
         '","diagnostics":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":4}},"severity":1,"source":"delphilsp-stub","message":"' + $message + '"}]}}'
}
function DocNote([string]$method, [string]$uri) {
  return Frame ('{"jsonrpc":"2.0","method":"' + $method + '","params":{"textDocument":{"uri":"' + $uri + '","version":2},"contentChanges":[]}}')
}

Write-Host ''
Write-Host 'run_lsp_proxy_merge_diagnostics_guard -- publishDiagnostics merge (A1)' -ForegroundColor Cyan

# --- the stub server, built the same way the sibling guards build it --------
$fixtureDir = "$PSScriptRoot\fixtures\lspproxy"
$outDir     = Join-Path $WorkDir 'stub'
New-Item -ItemType Directory $outDir | Out-Null
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$null = cmd /c "call `"$rs`" && cd /d `"$fixtureDir`" && dcc64 -CC -E`"$outDir`" -N0`"$outDir`" LspStubServer.dpr" 2>&1
$stub = "$outDir\LspStubServer.exe"
Check 'LspStubServer.exe built' (Test-Path $stub) $stub
if (-not (Test-Path $stub)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

# --- fixtures, with their positive controls ----------------------------------
$dirty = Join-Path $WorkDir 'Dirty.pas'
$clean = Join-Path $WorkDir 'Clean.pas'
[IO.File]::WriteAllText($dirty, "unit Dirty;`r`n`r`ninterface`r`n`r`nprocedure Foo;`r`n`r`nimplementation`r`n`r`nprocedure Foo;`r`nbegin`r`n  try`r`n    Foo;`r`n  except`r`n  end;`r`nend;`r`n`r`nend.`r`n", [Text.Encoding]::ASCII)
[IO.File]::WriteAllText($clean, "unit Clean;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`nend.`r`n", [Text.Encoding]::ASCII)
$dirtyLint = @(& $Exe lint $dirty --json 2>$null | Out-String | ConvertFrom-Json)
$cleanLint = @(& $Exe lint $clean --json 2>$null | Out-String | ConvertFrom-Json)
Check 'positive control: the dirty fixture trips >= 1 lint finding' (@($dirtyLint | Where-Object { $_.start_line -gt 0 }).Count -ge 1) ("findings=$(@($dirtyLint | Where-Object { $_.start_line -gt 0 }).Count)")
Check 'control: the clean fixture trips none' (@($cleanLint | Where-Object { $_.start_line -gt 0 }).Count -eq 0) ("findings=$(@($cleanLint | Where-Object { $_.start_line -gt 0 }).Count)")
$dirtyUri = Uri $dirty
$cleanUri = Uri $clean

$plainArgs = @('lsp', '--proxy', '--delphi-lsp', $stub)
$offArgs   = @('lsp', '--proxy', '--merge-budget-ms', '20000', '--delphi-lsp', $stub)
$onArgs    = @('lsp', '--proxy', '--merge-diagnostics', '--merge-budget-ms', '20000', '--delphi-lsp', $stub)
$zeroArgs  = @('lsp', '--proxy', '--merge-diagnostics', '--merge-budget-ms', '0', '--delphi-lsp', $stub)
$defArgs   = @('lsp', '--proxy', '--merge-diagnostics', '--delphi-lsp', $stub)   # NO --merge-budget-ms: the shipping default
$script:PushN = 0
function Push([string[]]$argv, [string]$body) {
  $script:PushN++
  $f = Join-Path $WorkDir "push$($script:PushN).bin"
  [IO.File]::WriteAllBytes($f, (Frame $body))
  return Invoke-Raw $Exe $argv ([byte[]]@()) @{ DRAGLINT_STUB_PUBLISH_FILE = $f }
}

# --- (a) ON, dirty: one merged notification ---------------------------------
Write-Host ''
Write-Host '(a) ON, dirty fixture: ONE notification carrying both sources' -ForegroundColor Cyan
$dirtyBody = PublishBody $dirtyUri 'stub-compiler-error-7f3a'
$aOn  = Push $onArgs $dirtyBody
$aPub = Publishes $aOn.Out
Check 'exactly one publishDiagnostics frame' ($aPub.Count -eq 1) ("count=$($aPub.Count)")
Check 'it carries the stub diagnostic'   ($aPub.Count -eq 1 -and ($aPub[0].Sources -contains 'delphilsp-stub')) ("sources=$($aPub[0].Sources -join ',')")
Check 'it carries a drag-lint diagnostic' ($aPub.Count -eq 1 -and ($aPub[0].Sources -contains 'drag-lint')) ("sources=$($aPub[0].Sources -join ',')")
Check 'its Content-Length is exact' ($aPub.Count -eq 1 -and $aPub[0].Frame.Declared -eq $aPub[0].Frame.Actual -and $aPub[0].Frame.Declared -eq [Text.Encoding]::UTF8.GetByteCount($aPub[0].Frame.Body)) ''

# --- (e) OFF vs ON ----------------------------------------------------------
Write-Host ''
Write-Host '(e) OFF is the plain relay; ON differs' -ForegroundColor Cyan
$ePlain = Push $plainArgs $dirtyBody
$eOff   = Push $offArgs   $dirtyBody
$eWant  = [Text.Encoding]::ASCII.GetBytes('STUB-PREAMBLE-BEGIN') + (Frame $dirtyBody) + [Text.Encoding]::ASCII.GetBytes('STUB-TRAILER-END')
Check 'plain relay = the pushed bytes verbatim' (Same $ePlain.Out ([byte[]]$eWant)) ("plain=$($ePlain.Out.Length) want=$($eWant.Length)")
Check 'OFF (budget flag only) = the plain relay, byte for byte' (Same $eOff.Out $ePlain.Out) ("off=$($eOff.Out.Length) plain=$($ePlain.Out.Length)")
Check 'ON differs from the plain relay (positive control)' (-not (Same $aOn.Out $ePlain.Out)) ("on=$($aOn.Out.Length) plain=$($ePlain.Out.Length)")

# --- (b) ON, clean ----------------------------------------------------------
Write-Host ''
Write-Host '(b) ON, clean fixture: byte-identical' -ForegroundColor Cyan
$cleanBody = PublishBody $cleanUri 'stub-compiler-error-7f3a'
$bOn    = Push $onArgs    $cleanBody
$bPlain = Push $plainArgs $cleanBody
Check 'clean fixture: ON = plain relay' (Same $bOn.Out $bPlain.Out) ("on=$($bOn.Out.Length) plain=$($bPlain.Out.Length)")

# --- (c) FAIL OPEN on invalid JSON ------------------------------------------
Write-Host ''
Write-Host '(c) FAIL OPEN: invalid JSON matching the pre-check' -ForegroundColor Cyan
$badBody = '{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"' + $dirtyUri + '", BROKEN'
$cOn    = Push $onArgs    $badBody
$cPlain = Push $plainArgs $badBody
Check 'invalid JSON: ON = plain relay' (Same $cOn.Out $cPlain.Out) ("on=$($cOn.Out.Length) plain=$($cPlain.Out.Length)")
$cLines = @((Utf8 $cOn.Err) -split "\r?\n" | Where-Object { $_ -match 'merge' })
Check 'exactly one stderr line names the merge' ($cLines.Count -eq 1) ("lines=$($cLines.Count) err=$(Utf8 $cOn.Err)")

# --- (d) budget 0 -----------------------------------------------------------
Write-Host ''
Write-Host '(d) --merge-budget-ms 0: byte-identical' -ForegroundColor Cyan
$dZero = Push $zeroArgs $dirtyBody
Check 'budget 0, dirty fixture: = plain relay' (Same $dZero.Out $ePlain.Out) ("zero=$($dZero.Out.Length) plain=$($ePlain.Out.Length)")

# --- (f) scripted completion reply ------------------------------------------
Write-Host ''
Write-Host '(f) a completion reply relays byte-identical with merge ON' -ForegroundColor Cyan
$script = Join-Path $WorkDir 'script.tsv'
[IO.File]::WriteAllText($script, "textDocument/completion`t0`t{`"isIncomplete`":false,`"items`":[{`"label`":`"StubItem`"}]}`r`n")
$fReq = Frame ('{"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"' + $dirtyUri + '"},"position":{"line":0,"character":0}}}')
$fOn  = Invoke-Raw $Exe $onArgs    ([byte[]]$fReq) @{ DRAGLINT_STUB_SCRIPT = $script }
$fOff = Invoke-Raw $Exe $plainArgs ([byte[]]$fReq) @{ DRAGLINT_STUB_SCRIPT = $script }
Check 'completion reply: ON = plain relay' (Same $fOn.Out $fOff.Out) ("on=$($fOn.Out.Length) off=$($fOff.Out.Length)")
Check 'the scripted item came back' ((Ascii $fOn.Out).Contains('StubItem')) ''

# --- (g) DIRTY buffer -------------------------------------------------------
Write-Host ''
Write-Host '(g) DIRTY: didChange -> unmerged, didSave -> merged' -ForegroundColor Cyan
# Echo mode: every client frame comes back as a server frame, in order, so a
# publish frame reaches the S>C interceptor AFTER the C>S side has seen every
# notification before it on the wire. Two runs, not one: the C>S pump races
# ahead of the echo, so in ONE run a later didSave would already have cleared
# the URI by the time the first publish comes back.
$pub1 = PublishBody $dirtyUri 'stub-after-change-1111'
$pub2 = PublishBody $dirtyUri 'stub-after-save-2222'
$g1In = (DocNote 'textDocument/didChange' $dirtyUri) + (Frame $pub1)
$g2In = (DocNote 'textDocument/didChange' $dirtyUri) + (DocNote 'textDocument/didSave' $dirtyUri) + (Frame $pub2)
$g1On = Invoke-Raw $Exe $onArgs ([byte[]]$g1In)
$g2On = Invoke-Raw $Exe $onArgs ([byte[]]$g2In)
$gPub = (Publishes $g1On.Out) + (Publishes $g2On.Out)
$g1 = @($gPub | Where-Object { $_.Frame.Body.Contains('stub-after-change-1111') })
$g2 = @($gPub | Where-Object { $_.Frame.Body.Contains('stub-after-save-2222') })
Check 'after didChange: the publish is the original bytes' ($g1.Count -eq 1 -and $g1[0].Frame.Body -ceq $pub1) ("count=$($g1.Count) sources=$($g1[0].Sources -join ',')")
Check 'after didSave: the publish is merged (drag-lint present)' ($g2.Count -eq 1 -and ($g2[0].Sources -contains 'drag-lint')) ("count=$($g2.Count) sources=$($g2[0].Sources -join ',')")

# --- (g2) didChange shapes the head scan must not misread (group-4 P3) -------
# Each shape: (body, expect dirty?, expected path: 'fast' | 'full' | 'any').
# The path is read from the test seam DRAGLINT_MERGE_TEST_FASTPATH=1, which
# makes the bounded head scan write one stderr line per didChange it takes:
# the plain layout proves the fast path RUNS; the others prove it declines.
Write-Host ''
Write-Host '(g2) DIRTY via didChange shapes the bounded head scan cannot (or must not) take literally' -ForegroundColor Cyan
$bigText = ('x' * 6000) | ConvertTo-Json
$escUri  = $dirtyUri.Replace('/', '\/')
$fastTag = 'test: didChange read from the head'
$shapes = [ordered]@{
  'plain layout (positive control: fast path taken)' = @(('{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"' + $dirtyUri + '","version":2},"contentChanges":[{"text":' + $bigText + '}]}}'), $true, 'fast')
  'contentChanges first, uri beyond the 4 KB head'  = @(('{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"contentChanges":[{"text":' + $bigText + '}],"textDocument":{"uri":"' + $dirtyUri + '","version":2}}}'), $true, 'full')
  'uri written with escaped slashes'                = @(('{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"' + $escUri + '","version":2},"contentChanges":[{"text":"x"}]}}'), $true, 'full')
  'an escaped \"uri\" inside the text comes first'  = @(('{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"contentChanges":[{"text":"a \"uri\":\"file:///C:/elsewhere/Other.pas\" b"}],"textDocument":{"uri":"' + $dirtyUri + '","version":2}}}'), $true, 'any')
  'a NESTED "method":"didChange" in a non-didChange frame' = @(('{"jsonrpc":"2.0","params":{"textDocument":{"uri":"' + $dirtyUri + '"},"note":{"method":"textDocument/didChange"}},"method":"textDocument/didFrob"}'), $false, 'full')
}
$gN = 0
foreach ($k in $shapes.Keys) {
  $gN++
  $sh   = $shapes[$k]
  $pubG = PublishBody $dirtyUri "stub-g2-shape-$gN"
  $rG   = Invoke-Raw $Exe $onArgs ([byte[]]((Frame $sh[0]) + (Frame $pubG))) @{ DRAGLINT_MERGE_TEST_FASTPATH = '1' }
  $pG   = @(Publishes $rG.Out | Where-Object { $_.Frame.Body.Contains("stub-g2-shape-$gN") })
  $srcs = if ($pG.Count) { $pG[0].Sources -join ',' } else { '' }
  if ($sh[1]) {
    Check "$($k): the publish after it is the original bytes (URI dirty)" ($pG.Count -eq 1 -and $pG[0].Frame.Body -ceq $pubG) ("count=$($pG.Count) sources=$srcs")
  } else {
    Check "$($k): the publish after it is MERGED (URI not dirty)" ($pG.Count -eq 1 -and ($pG[0].Sources -contains 'drag-lint')) ("count=$($pG.Count) sources=$srcs")
  }
  $fast = (Utf8 $rG.Err).Contains($fastTag)
  if ($sh[2] -eq 'fast') { Check "$($k): the head scan took it (seam line on stderr)" $fast '' }
  elseif ($sh[2] -eq 'full') { Check "$($k): the head scan declined it (no seam line)" (-not $fast) '' }
}
# --- (h) UTF-8 byte count ---------------------------------------------------
# --- (i) DEFAULT budget: the first publish after didOpen is merged (I1) ------
Write-Host ''
Write-Host '(i) default budget: didOpen, then a later publish -> merged (cold linter warmed off the relay path)' -ForegroundColor Cyan
$pubI = PublishBody $dirtyUri 'stub-default-budget-3333'
foreach ($run in 1, 2) {
  $iOn  = Invoke-Raw $Exe $defArgs ([byte[]](DocNote 'textDocument/didOpen' $dirtyUri)) @{} ([byte[]](Frame $pubI)) 6000
  $iPub = @(Publishes $iOn.Out | Where-Object { $_.Frame.Body.Contains('stub-default-budget-3333') })
  Check "run ${run}: the first publish is merged (drag-lint present)" ($iPub.Count -eq 1 -and ($iPub[0].Sources -contains 'drag-lint')) ("count=$($iPub.Count) sources=$($iPub[0].Sources -join ',')")
}

# --- (j) didClose / didOpen clear the dirty flag (M1, M5) -----------------------
Write-Host ''
Write-Host '(j) didChange + didClose (or didOpen) -> the next publish is merged' -ForegroundColor Cyan
$pubJ1 = PublishBody $dirtyUri 'stub-after-close-4444'
$pubJ2 = PublishBody $dirtyUri 'stub-after-open-5555'
$j1 = Invoke-Raw $Exe $onArgs ([byte[]]((DocNote 'textDocument/didChange' $dirtyUri) + (DocNote 'textDocument/didClose' $dirtyUri) + (Frame $pubJ1)))
# didOpen warms the linter on the worker; the publish follows later so it is not refused as busy
$j2 = Invoke-Raw $Exe $onArgs ([byte[]]((DocNote 'textDocument/didChange' $dirtyUri) + (DocNote 'textDocument/didOpen' $dirtyUri))) @{} ([byte[]](Frame $pubJ2)) 6000
$jp1 = @(Publishes $j1.Out | Where-Object { $_.Frame.Body.Contains('stub-after-close-4444') })
$jp2 = @(Publishes $j2.Out | Where-Object { $_.Frame.Body.Contains('stub-after-open-5555') })
Check 'after didChange + didClose: the publish is merged' ($jp1.Count -eq 1 -and ($jp1[0].Sources -contains 'drag-lint')) ("count=$($jp1.Count)")
Check 'after didChange + didOpen: the publish is merged' ($jp2.Count -eq 1 -and ($jp2[0].Sources -contains 'drag-lint')) ("count=$($jp2.Count)")

# --- (k) a publish DURING the warm-up is not an over-budget event (A3 fix 1) ----
Write-Host ''
Write-Host '(k) didOpen + an immediate publish (default budget): no "over its budget" line' -ForegroundColor Cyan
# The publish lands while the first-didOpen warm-up (cold TLinter.Create, seconds)
# still occupies the worker. That is the warm-up, not a dead merge: the frame is
# forwarded unmerged, silently. Positive control: the SAME engine, with no
# didOpen (so no warm-up) and a 1 ms budget, DOES write the line -- the stderr
# capture and the message text are live.
$pubK = PublishBody $dirtyUri 'stub-during-warmup-6666'
$k1   = Invoke-Raw $Exe $defArgs ([byte[]]((DocNote 'textDocument/didOpen' $dirtyUri) + (Frame $pubK)))
$kp   = @(Publishes $k1.Out | Where-Object { $_.Frame.Body.Contains('stub-during-warmup-6666') })
Check 'the publish arrived during the warm-up (forwarded unmerged)' ($kp.Count -eq 1 -and -not ($kp[0].Sources -contains 'drag-lint')) ("count=$($kp.Count) sources=$($kp[0].Sources -join ',')")
Check 'no "over its ... budget" line during the warm-up' (-not ((Utf8 $k1.Err) -match 'over its \d+ ms budget')) ("err=$(Utf8 $k1.Err)")
$oneArgs = @('lsp', '--proxy', '--merge-diagnostics', '--merge-budget-ms', '1', '--delphi-lsp', $stub)
$k2 = Push $oneArgs (PublishBody $dirtyUri 'stub-no-warmup-7777')
Check 'positive control: no warm-up, 1 ms budget -> the line IS written' ((Utf8 $k2.Err) -match 'over its 1 ms budget') ("err=$(Utf8 $k2.Err)")

Write-Host ''
Write-Host '(h) non-ASCII message: Content-Length is the UTF-8 byte count' -ForegroundColor Cyan
$uMsg  = 'stub-umlaut-' + [char]0x00FC + '-end'
$hOn   = Push $onArgs (PublishBody $dirtyUri $uMsg)
$hPub  = Publishes $hOn.Out
$hOk   = $hPub.Count -eq 1
Check 'the frame was merged (drag-lint present)' ($hOk -and ($hPub[0].Sources -contains 'drag-lint')) ("count=$($hPub.Count)")
Check 'Content-Length = UTF-8 byte length of the body' ($hOk -and $hPub[0].Frame.Declared -eq $hPub[0].Frame.Actual -and $hPub[0].Frame.Declared -eq [Text.Encoding]::UTF8.GetByteCount($hPub[0].Frame.Body)) ("declared=$($hPub[0].Frame.Declared) bytes=$([Text.Encoding]::UTF8.GetByteCount([string]$hPub[0].Frame.Body))")
Check 'the stub message survives intact' ($hOk -and (@($hPub[0].Json['params']['diagnostics'] | Where-Object { $_['message'] -ceq $uMsg }).Count -eq 1)) ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\draglint_lspproxy_mergediag_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
