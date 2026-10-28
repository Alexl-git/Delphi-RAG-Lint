#Requires -Version 7
# dl:serial: LSP proxy family. Spawns and reaps LspStub children, like the
#   sibling run_lsp_proxy_*guard.ps1 scripts.
<#
  run_lsp_proxy_preprocess_guard.ps1 -- `lsp --proxy --merge-diagnostics` must
  merge findings linted from the PREPROCESSED text, exactly as plain `lsp` and
  `lint` do (LSP-BACKLOG C14).

  THE DEFECT THIS PINS: C8 made the plain `lsp` startup branch call
  TAstParseCache.SetPreprocess and C10 added the per-file define resolver, but
  the --proxy branch returns before both, so the merge worker linted the RAW
  bytes: a routine with {$IFDEF MSWINDOWS} / {$IFDEF POSIX} alternative bodies
  got a false parser-error on its second `end;`, appended to DelphiLSP's own
  publishDiagnostics. The fix routes both modes through ONE setup routine.

  Fixtures (the run_lsp_preprocess_guard ones), each pushed by the stub server
  as a publishDiagnostics for the fixture's URI:
    alt-bodies  two {$IFDEF} alternative bodies          -> 0 drag-lint parser-error
    dead-error  garbage inside the INACTIVE POSIX branch -> 0 (preprocessed away)
    live-error  the same garbage in the ACTIVE branch    -> >= 1 (POSITIVE CONTROL:
                the merge still publishes parser-error; the fix is preprocessing,
                not suppression)
  plus parity with `lint --json`, the stub's own diagnostic surviving in every
  merged frame, and a setup check that `lint --no-preprocess` DOES report
  parser-error on alt-bodies (the fixture needs the preprocessor).

  The proxy guards default -Exe to dll-win64; a lane passes its own engine.
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_lspproxy_pp_$PID"
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
function Write-Ascii($p, $t) { [System.IO.File]::WriteAllText($p, $t, [System.Text.Encoding]::ASCII) }

$StubEnvVars = @('DRAGLINT_STUB_PUBLISH_FILE', 'DRAGLINT_STUB_SCRIPT', 'DRAGLINT_STUB_LOG', 'DRAGLINT_STUB_LINGER', 'DRAGLINT_MERGE_TEST_EMPTY_REPLACEMENT')
foreach ($v in $StubEnvVars) { [Environment]::SetEnvironmentVariable($v, $null, 'Process') }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Invoke-Raw {
  param([string]$exe, [string[]]$argv, [hashtable]$envs = @{})
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
  try { $p.StandardInput.BaseStream.Close() } catch { }
  $done = $p.WaitForExit(60000)
  if (-not $done) { try { $p.Kill($true) } catch { } }
  [void]$outT.Wait(5000); [void]$errT.Wait(5000)
  return [pscustomobject]@{ Out = $outMs.ToArray(); Err = $errMs.ToArray(); Code = $(if ($done) { $p.ExitCode } else { -999 }) }
}
function Frame([string]$body) {
  $bb = [System.Text.Encoding]::UTF8.GetBytes($body)
  $h  = [System.Text.Encoding]::ASCII.GetBytes("Content-Length: $($bb.Length)`r`n`r`n")
  return [byte[]]($h + $bb)
}
# The publishDiagnostics frames of an output stream, parsed (stub preamble skipped).
function Publishes([byte[]]$b) {
  $res = @()
  $s = [System.Text.Encoding]::ASCII.GetString($b)
  $pos = 0
  while ($true) {
    $m = [regex]::Match($s.Substring($pos), '(?is)Content-Length:\s*(\d+)[^\r]*\r\n(?:[^\r]*\r\n)*?\r\n')
    if (-not $m.Success) { break }
    $start = $pos + $m.Index + $m.Length
    $avail = [Math]::Min([int]$m.Groups[1].Value, $b.Length - $start)
    $body  = [System.Text.Encoding]::UTF8.GetString($b, $start, $avail)
    $pos   = $start + $avail
    try { $j = $body | ConvertFrom-Json -AsHashtable } catch { continue }
    if ($j -and ($j['method'] -eq 'textDocument/publishDiagnostics')) { $res += ,$j }
  }
  return ,$res
}

Write-Host ''
Write-Host 'run_lsp_proxy_preprocess_guard -- the proxy merge lints preprocessed text (C14)' -ForegroundColor Cyan

# --- the stub server, built the same way the sibling guards build it --------
$fixtureDir = "$PSScriptRoot\fixtures\lspproxy"
$outDir     = Join-Path $WorkDir 'stub'
New-Item -ItemType Directory $outDir | Out-Null
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$null = cmd /c "call `"$rs`" && cd /d `"$fixtureDir`" && dcc64 -CC -E`"$outDir`" -N0`"$outDir`" LspStubServer.dpr" 2>&1
$stub = "$outDir\LspStubServer.exe"
Check 'LspStubServer.exe built' (Test-Path $stub) $stub
if (-not (Test-Path $stub)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

# ---------- fixtures (run_lsp_preprocess_guard's) ----------
function New-Fixture([string]$Name, [string]$WinBody, [string]$PosixBody) {
  $lines = @(
    'unit uPp;', '', 'interface', '', 'function CurDir: string;', 'procedure Other(X: TObject);', '',
    'implementation', '', 'function CurDir: string;',
    '{$IFDEF MSWINDOWS}', 'begin', $WinBody, 'end;', '{$ENDIF}',
    '{$IFDEF POSIX}', 'begin', $PosixBody, 'end;', '{$ENDIF}', '',
    'procedure Other(X: TObject);', 'begin', '  X.Free;', '  X := nil;', 'end;', '', 'end.'
  )
  $dir = Join-Path $WorkDir $Name
  New-Item -ItemType Directory -Force $dir | Out-Null
  $f = Join-Path $dir 'uPp.pas'
  Write-Ascii $f (($lines -join "`r`n") + "`r`n")
  return $f
}
$Good    = "  Result := 'C:\';"
$Garbage = '  Result := := ) ;'
$alt  = New-Fixture 'alt'  $Good $Good
$dead = New-Fixture 'dead' $Good $Garbage
$live = New-Fixture 'live' $Garbage $Good

# `lint --json` is a bare array; the line field is start_line, the id is rule.
function CliLines([string]$PasFile, [string[]]$Extra = @()) {
  $raw = (& $Exe lint $PasFile --json @Extra 2>$null) -join "`n"
  $arr = @()
  if ($raw.Trim()) { $arr = @($raw | ConvertFrom-Json) }
  return ,@($arr | Where-Object { $_.rule -eq 'parser-error' } | ForEach-Object { [int]$_.start_line })
}
# drag-lint parser-error lines in the merged publish for the fixture; 'NO-PUBLISH' /
# 'NO-STUB' when the frame is missing or lost DelphiLSP's own diagnostic.
$script:PushN = 0
function ProxyLines([string]$PasFile) {
  $script:PushN++
  $uri  = 'file:///' + ($PasFile -replace '\\', '/')
  $body = '{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"' + $uri +
          '","diagnostics":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":4}},"severity":1,"source":"delphilsp-stub","message":"stub-c14"}]}}'
  $f = Join-Path $WorkDir "push$($script:PushN).bin"
  [IO.File]::WriteAllBytes($f, (Frame $body))
  $r = Invoke-Raw $Exe @('lsp', '--proxy', '--merge-diagnostics', '--merge-budget-ms', '20000', '--delphi-lsp', $stub) @{ DRAGLINT_STUB_PUBLISH_FILE = $f }
  $pubs = Publishes $r.Out
  if ($pubs.Count -ne 1) { return ,@('NO-PUBLISH') }
  $diags = @($pubs[0]['params']['diagnostics'])
  if (-not ($diags | Where-Object { $_['source'] -eq 'delphilsp-stub' })) { return ,@('NO-STUB') }
  return ,@($diags | Where-Object { $_['source'] -eq 'drag-lint' -and $_['code'] -eq 'parser-error' } |
            ForEach-Object { [int]$_['range']['start']['line'] + 1 })
}

Write-Host 'SETUP: the fixture needs the preprocessor' -ForegroundColor Cyan
$raw = CliLines $alt @('--no-preprocess')
Check 'lint --no-preprocess reports parser-error on the alternative bodies' ($raw.Count -ge 1) ("cli=[" + ($raw -join ',') + "]")
$pre = CliLines $alt
Check 'lint (preprocessed) reports none' ($pre.Count -eq 0) ("cli=[" + ($pre -join ',') + "]")

Write-Host ''
Write-Host 'lsp --proxy --merge-diagnostics merges preprocessed findings' -ForegroundColor Cyan
foreach ($c in @(
    @{ Name = 'alt-bodies';                   File = $alt;  Zero = $true  },
    @{ Name = 'dead-error (inactive branch)'; File = $dead; Zero = $true  },
    @{ Name = 'live-error (POSITIVE CONTROL)'; File = $live; Zero = $false })) {
  $px  = ProxyLines $c.File
  $cli = CliLines $c.File
  $d = "proxy=[" + ($px -join ',') + "] cli=[" + ($cli -join ',') + "]"
  $framed = ($px -notcontains 'NO-PUBLISH') -and ($px -notcontains 'NO-STUB')
  Check "$($c.Name) : one merged frame keeps the stub diagnostic" $framed $d
  $countOk = if ($c.Zero) { $framed -and $px.Count -eq 0 } else { $framed -and $px.Count -ge 1 }
  Check "$($c.Name) : drag-lint parser-error count" $countOk $d
  Check "$($c.Name) : parity with lint --json" (($px -join ',') -eq ($cli -join ',')) $d
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($v in @('DRAGLINT_STUB_PUBLISH_FILE')) { [Environment]::SetEnvironmentVariable($v, $null, 'Process') }
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
