#Requires -Version 7
# dl:serial: LSP proxy family. Spawns and reaps LspStub children (see run_lsp_proxy_merge_diagnostics_guard.ps1).
<#
  run_lsp_proxy_merge_fullrules_guard.ps1 -- 1.52.3 MERGE-FULLRULES:
  `lsp --proxy --merge-diagnostics --full-rules` merges the FULL `lint <file> --json`
  set into DelphiLSP's publishDiagnostics, as plain `lsp --full-rules` publishes it.

  Before the fix the proxy ignored --full-rules: its merge always ran the in-process
  SUBSET (BuildDiagnostics), so VS Code showed 11 findings on CLI.Export.pas where
  plain `lsp --full-rules` / `lint` showed 14 (DIAG 2026-11-20).

  Checks:
    (control) `lint --json` reports missing-inherited-ctor (a built-in the subset lacks);
    (control) WITHOUT --full-rules the merged set lacks it (so the guard can fail);
    (a) WITH --full-rules the LAST publish for the URI carries the stub diagnostic AND
        exactly the rule ids `lint --json` reports (same count, same multiset);
    (b) stderr carries the "full-rules <file> <ms> ms <n> findings" cost line, n = that count.

  -Exe defaults to dll-win64; a lane passes its own engine. Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\draglint_lspproxy_fullrules_$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
foreach ($v in @('DRAGLINT_STUB_PUBLISH_FILE', 'DRAGLINT_STUB_SCRIPT', 'DRAGLINT_STUB_LOG', 'DRAGLINT_STUB_LINGER', 'DRAGLINT_FULLRULES_CHILD_EXE', 'DRAGLINT_MERGE_TEST_LINT_DELAY_MS')) {
  [Environment]::SetEnvironmentVariable($v, $null, 'Process')
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Invoke-Raw {
  param([string]$exe, [string[]]$argv, [byte[]]$c1, [hashtable]$envs = @{}, [byte[]]$c2 = $null, [int]$delayMs = 0)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe
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
  $done = $p.WaitForExit(90000)
  if (-not $done) { try { $p.Kill($true) } catch { } }
  [void]$outT.Wait(5000); [void]$errT.Wait(5000)
  return [pscustomobject]@{ Out = $outMs.ToArray(); Err = $errMs.ToArray(); Code = $(if ($done) { $p.ExitCode } else { -999 }) }
}
function Utf8([byte[]]$b) { if (-not $b) { return '' } [System.Text.Encoding]::UTF8.GetString($b) }
function Frame([string]$body) {
  $bb = [System.Text.Encoding]::UTF8.GetBytes($body)
  $h  = [System.Text.Encoding]::ASCII.GetBytes("Content-Length: $($bb.Length)`r`n`r`n")
  return [byte[]]($h + $bb)
}
function Split-Frames([byte[]]$b) {
  $res = @()
  $s = [System.Text.Encoding]::ASCII.GetString($b)
  $pos = 0
  while ($true) {
    $m = [regex]::Match($s.Substring($pos), '(?is)Content-Length:\s*(\d+)[^\r]*\r\n(?:[^\r]*\r\n)*?\r\n')
    if (-not $m.Success) { break }
    $start = $pos + $m.Index + $m.Length
    $decl  = [int]$m.Groups[1].Value
    $avail = [Math]::Min($decl, $b.Length - $start)
    $res  += [pscustomobject]@{ Body = [System.Text.Encoding]::UTF8.GetString($b, $start, $avail) }
    $pos   = $start + $avail
  }
  return ,$res
}
# publishDiagnostics frames whose body contains $tag, parsed, in stream order.
function Publishes([byte[]]$b, [string]$tag) {
  $res = @()
  foreach ($f in (Split-Frames $b)) {
    if (-not $f.Body.Contains($tag)) { continue }
    try { $j = $f.Body | ConvertFrom-Json -AsHashtable | ForEach-Object { $_ } } catch { continue }
    if ($j -and ($j['method'] -eq 'textDocument/publishDiagnostics')) {
      $d = @($j['params']['diagnostics'])
      $res += [pscustomobject]@{
        Sources = @($d | ForEach-Object { $_['source'] })
        Codes   = @($d | Where-Object { $_['source'] -like 'drag-lint*' } | ForEach-Object { [string]$_['code'] } | Sort-Object)
      }
    }
  }
  return ,$res
}

Write-Host ''
Write-Host 'run_lsp_proxy_merge_fullrules_guard -- proxy merge honours --full-rules (1.52.3)' -ForegroundColor Cyan

$fixtureDir = "$PSScriptRoot\fixtures\lspproxy"
$outDir     = Join-Path $WorkDir 'stub'
New-Item -ItemType Directory $outDir | Out-Null
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$null = & { $ErrorActionPreference = 'Continue'; cmd /c "call `"$rs`" && cd /d `"$fixtureDir`" && dcc64 -CC -E`"$outDir`" -N0`"$outDir`" LspStubServer.dpr" 2>&1 | ForEach-Object { "$_" } }
$stub = "$outDir\LspStubServer.exe"
Check 'LspStubServer.exe built' (Test-Path $stub) $stub
if (-not (Test-Path $stub)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

# missing-inherited-ctor and code-after-exit: built-ins ON by default that the subset does not run
# (the fixture of run_lsp_full_rules_guard.ps1).
$src = @(
  'unit FxDirty;', '', 'interface', '', 'type', '  TA = class', '    constructor Create;', '  end;', '',
  'implementation', '', 'constructor TA.Create;', 'begin', '  Writeln(1);', 'end;', '',
  'procedure Go(const S: string);', 'begin', '  Exit;', '  Writeln(S);', 'end;', '', 'end.') -join "`r`n"
$dirty = Join-Path $WorkDir 'FxDirty.pas'
[IO.File]::WriteAllText($dirty, $src + "`r`n", [Text.Encoding]::ASCII)
$lint = @((& { $ErrorActionPreference = 'Continue'; & $Exe lint $dirty --json 2>$null } | Out-String | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ })
$want = @($lint | ForEach-Object { if ($_.rule) { [string]$_.rule } elseif ($_.rule_id) { [string]$_.rule_id } } | Where-Object { $_ } | Sort-Object)
Check 'CONTROL: `lint --json` reports missing-inherited-ctor' ($want -contains 'missing-inherited-ctor') ("rules=$($want -join ',')")

$uri  = 'file:///' + ($dirty -replace '\\', '/')
$tag  = 'stub-fullrules-4e1c'
$body = '{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"' + $uri +
        '","diagnostics":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":4}},"severity":1,"source":"delphilsp-stub","message":"' + $tag + '"}]}}'
$pushF = Join-Path $WorkDir 'push.bin'
[IO.File]::WriteAllBytes($pushF, (Frame $body))
$init = Frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
$keep = Frame '{"jsonrpc":"2.0","method":"$/setTrace","params":{"value":"off"}}'
$base = @('lsp', '--proxy', '--merge-diagnostics', '--merge-budget-ms', '20000', '--delphi-lsp', $stub)

# --- control: without --full-rules the merge is the subset ---------------------
$off  = Invoke-Raw $Exe $base $init @{ DRAGLINT_STUB_PUBLISH_FILE = $pushF } $keep 8000
$offP = Publishes $off.Out $tag
Check 'CONTROL: without --full-rules the publish arrives (the subset finds nothing here: forwarded as is)' ($offP.Count -ge 1 -and ($offP[-1].Sources -contains 'delphilsp-stub')) ("count=$($offP.Count)")
Check 'CONTROL: without --full-rules the merged set lacks missing-inherited-ctor (subset)' ($offP.Count -ge 1 -and -not ($offP[-1].Codes -contains 'missing-inherited-ctor')) ("codes=$($offP[-1].Codes -join ',')")

# --- (a) + (b) with --full-rules -------------------------------------------------
$on  = Invoke-Raw $Exe ($base + @('--full-rules')) $init @{ DRAGLINT_STUB_PUBLISH_FILE = $pushF } $keep 45000
$onP = Publishes $on.Out $tag
$last = if ($onP.Count -ge 1) { $onP[-1] } else { $null }
Check '(a) the last publish carries the stub diagnostic' ($last -and ($last.Sources -contains 'delphilsp-stub')) ("count=$($onP.Count)")
Check '(a) the last publish carries missing-inherited-ctor' ($last -and ($last.Codes -contains 'missing-inherited-ctor')) ("codes=$($last.Codes -join ',')")
Check '(a) merged drag-lint count = `lint --json` count' ($last -and $last.Codes.Count -eq $want.Count) ("merged=$($last.Codes.Count) lint=$($want.Count)")
Check '(a) merged rule ids = `lint --json` rule ids' ($last -and (($last.Codes -join ',') -eq ($want -join ','))) ("merged=$($last.Codes -join ',') lint=$($want -join ',')")
$m = [regex]::Match((Utf8 $on.Err), 'full-rules (.+?) (\d+) ms (\d+) findings')
Check '(b) stderr carries the full-rules cost line' $m.Success ''
Check '(b) its count = `lint --json` count' ($m.Success -and [int]$m.Groups[3].Value -eq $want.Count) ("line=[$($m.Value)]")

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
