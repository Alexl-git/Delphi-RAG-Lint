#Requires -Version 7
# dl:serial: spawns LspStubServer children (scripted fake DelphiLSP); joins the LSP proxy family quarantine.
<#
  run_verify_index_guard.ps1 -- `verify-index` (1.53.0 LSP1-VERB, status internal) against a SCRIPTED
  fake DelphiLSP (tests\autotest\fixtures\lspproxy\LspStubServer.dpr, position-keyed script lines).

  The battery must not need RAD Studio's language server, so the server side is the stub: it answers
  textDocument/definition per file:line:character and logs every frame it receives
  (DRAGLINT_STUB_LOG). The fixture is two units (fixtures\verifyindex); the index is real.

  Contract pinned (spec docs\superpowers\specs\2026-11-20-verify-index-design.md):
    AC4   --dry-run        -> sampled rows, no DelphiLSP started (no stub log);
    AC2   determinism      -> same db/sample/seed = same refIds in the same order;
    AC5/7 one planted mismatch -> exit 1, counts.mismatch 1, the row and the rate reported;
    AC8   null answer      -> retried once, then `empty` (kept out of the rate);
    AC9   no answer scripted -> `error`, the run continues;
    AC11  LocationLink[]   -> accepted;
    AC12  text report      -> summary line + one `mismatch` row;
    AC19  the child is gone when the verb exits;
    AC21  errors           -> exit 2, ERROR line on stderr, nothing on stdout;
    AC23  read-only        -> DB bytes unchanged.
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7. -Exe defaults to dll-win64; a lane passes its own build.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\draglint_verify_index_$PID"
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
foreach ($v in @('DRAGLINT_STUB_PUBLISH_FILE', 'DRAGLINT_STUB_SCRIPT', 'DRAGLINT_STUB_LOG', 'DRAGLINT_STUB_LINGER')) { [Environment]::SetEnvironmentVariable($v, $null, 'Process') }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. (Join-Path $PSScriptRoot 'lib\EngineCompanions.ps1')
[void](Initialize-EngineCompanions -Exe $Exe)
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

# Runs the engine with $argv and the given environment; returns Out / Err / Code.
function Invoke-Verb {
  param([string[]]$argv, [hashtable]$envs = @{}, [string]$cwd = $WorkDir)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  foreach ($a in $argv) { [void]$psi.ArgumentList.Add($a) }
  foreach ($k in $envs.Keys) { $psi.Environment[$k] = $envs[$k] }
  $psi.WorkingDirectory = $cwd
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow  = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $outT = $p.StandardOutput.ReadToEndAsync()
  $errT = $p.StandardError.ReadToEndAsync()
  $done = $p.WaitForExit(120000)
  if (-not $done) { try { $p.Kill($true) } catch { } }
  return [pscustomobject]@{ Out = $outT.Result; Err = $errT.Result; Code = $(if ($done) { $p.ExitCode } else { -999 }) }
}
function Uri([string]$path) { 'file:///' + ($path -replace '\\', '/') }
function Loc([string]$path, [int]$line0) {
  '{"uri":"' + (Uri $path) + '","range":{"start":{"line":' + $line0 + ',"character":0},"end":{"line":' + $line0 + ',"character":1}}}'
}
function LogCount([string]$log, [string]$method) {
  if (-not (Test-Path $log)) { return 0 }
  return @(Get-Content $log | Where-Object { $_ -like "$method`t*" }).Count
}

Write-Host ''
Write-Host 'run_verify_index_guard -- verify-index against a scripted fake DelphiLSP' -ForegroundColor Cyan

# --- the stub server ---------------------------------------------------------------
$fixtureDir = "$PSScriptRoot\fixtures\lspproxy"
$outDir     = Join-Path $WorkDir 'stub'
New-Item -ItemType Directory $outDir | Out-Null
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$null = & { $ErrorActionPreference = 'Continue'; cmd /c "call `"$rs`" && cd /d `"$fixtureDir`" && dcc64 -CC -E`"$outDir`" -N0`"$outDir`" LspStubServer.dpr" 2>&1 | ForEach-Object { "$_" } }
$stub = "$outDir\LspStubServer.exe"
Check 'LspStubServer.exe built' (Test-Path $stub) $stub
if (-not (Test-Path $stub)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

# --- the fixture and its index -------------------------------------------------------
$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir | Out-Null
Copy-Item "$PSScriptRoot\fixtures\verifyindex\*.pas" $srcDir
$db = Join-Path $WorkDir 'fixture.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $srcDir --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
Check 'fixture index built' (Test-Path $db)
$cfg = Join-Path $WorkDir 'fake.delphilsp.json'
[IO.File]::WriteAllText($cfg, '{"settings":{"project":"file:///x"}}', [Text.Encoding]::ASCII)
$sha0 = (Get-FileHash $db -Algorithm SHA256).Hash
$common = @('verify-index', '--db', $db, '--sample', '50')

# --- (1) dry run: AC4 + AC2 ------------------------------------------------------------
Write-Host ''
Write-Host '(1) --dry-run: sampled rows, no DelphiLSP; deterministic' -ForegroundColor Cyan
$logDry = Join-Path $WorkDir 'dry.log'
$d1 = Invoke-Verb ($common + @('--dry-run', '--json', '--delphi-lsp', $stub, '--delphi-lsp-config', $cfg)) @{ DRAGLINT_STUB_LOG = $logDry }
Check 'dry run exits 0' ($d1.Code -eq 0) "code=$($d1.Code) err=$($d1.Err)"
$dj = $null
try { $dj = $d1.Out | ConvertFrom-Json | ForEach-Object { $_ } } catch { }
Check 'dry run prints one JSON document' ($null -ne $dj) $d1.Out
$rows = @(if ($dj) { $dj.rows } else { })
Check 'at least 4 sampled rows' ($rows.Count -ge 4) "rows=$($rows.Count)"
Check 'every dry row is outcome sampled' (@($rows | Where-Object { $_.outcome -ne 'sampled' }).Count -eq 0)
Check 'no DelphiLSP started (no stub log)' (-not (Test-Path $logDry))
$d2 = Invoke-Verb ($common + @('--dry-run', '--json'))
$ids1 = ($rows | ForEach-Object { $_.refId }) -join ','
$ids2 = (@(($d2.Out | ConvertFrom-Json | ForEach-Object { $_ }).rows) | ForEach-Object { $_.refId }) -join ','
Check 'same seed -> same refIds in the same order (AC2)' ($ids1 -ne '' -and $ids1 -eq $ids2) "a=$ids1 b=$ids2"
$d3 = Invoke-Verb (@('verify-index', '--db', $db, '--sample', '50', '--seed', '2', '--dry-run', '--json'))
$ids3 = (@(($d3.Out | ConvertFrom-Json | ForEach-Object { $_ }).rows) | ForEach-Object { $_.refId }) -join ','
Check 'seed 2 -> a different order (AC2 control)' ($ids3 -ne $ids1) "seed1=$ids1 seed2=$ids3"
$d4 = Invoke-Verb (@('verify-index', '--db', $db, '--sample', '3', '--dry-run', '--json'))
Check '--sample 3 -> 3 rows (AC1)' (@(($d4.Out | ConvertFrom-Json | ForEach-Object { $_ }).rows).Count -eq 3)
if ($rows.Count -lt 4) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
$n = $rows.Count

# --- scripts ---------------------------------------------------------------------------
function RowKey($r) { 'textDocument/definition@' + (Split-Path $r.file -Leaf) + ':' + ($r.line - 1) + ':' + ($r.col - 1) }
function ScriptLines($rowAnswers) {
  $l = @("initialize`t0`t{`"capabilities`":{`"definitionProvider`":true}}", "shutdown`t0`tnull")
  for ($i = 0; $i -lt $rowAnswers.Count; $i++) { if ($null -ne $rowAnswers[$i]) { $l += ((RowKey $rows[$i]) + "`t0`t" + $rowAnswers[$i]) } }
  return $l
}
function Right($r) { Loc $r.dl.path ($r.dl.line - 1) }
function WriteScript([string]$name, $answers) {
  $p = Join-Path $WorkDir $name
  [IO.File]::WriteAllText($p, ((ScriptLines $answers) -join "`r`n") + "`r`n", [Text.Encoding]::ASCII)
  return $p
}
function VerbArgs([string[]]$extra) { $common + @('--delphi-lsp', $stub, '--delphi-lsp-config', $cfg, '--warmup-ms', '0') + $extra }

# --- (2) run A: one planted mismatch (AC5, AC7, AC12-14) ------------------------------------
Write-Host ''
Write-Host '(2) run A: one planted mismatch is reported with the rate and the row' -ForegroundColor Cyan
$ansA = @(for ($i = 0; $i -lt $n; $i++) { if ($i -eq 0) { Loc $rows[0].dl.path ($rows[0].dl.endLine + 50) } else { Right $rows[$i] } })
$logA = Join-Path $WorkDir 'a.log'
$envA = @{ DRAGLINT_STUB_SCRIPT = (WriteScript 'a.script' $ansA); DRAGLINT_STUB_LOG = $logA }
$ra = Invoke-Verb (VerbArgs @('--json')) $envA
$ja = $null
try { $ja = $ra.Out | ConvertFrom-Json | ForEach-Object { $_ } } catch { }
Check 'run A exits 1 (a mismatch)' ($ra.Code -eq 1) "code=$($ra.Code) err=$($ra.Err) out=$($ra.Out)"
Check 'counts.mismatch = 1' ($ja -and $ja.counts.mismatch -eq 1) $ra.Out
Check 'counts.match = n - 1' ($ja -and $ja.counts.match -eq ($n - 1)) "n=$n"
Check 'rate = 1/n' ($ja -and [Math]::Abs($ja.rate - 1.0 / $n) -lt 1e-4) "rate=$($ja.rate)"
Check 'rows holds exactly the planted row' ($ja -and @($ja.rows).Count -eq 1 -and $ja.rows[0].refId -eq $rows[0].refId -and $ja.rows[0].outcome -eq 'mismatch')
Check 'the mismatch row carries the LSP location' ($ja -and @($ja.rows[0].lsp).Count -eq 1 -and $ja.rows[0].lsp[0].line -eq ($rows[0].dl.endLine + 51))
Check 'stub saw initialize' ((LogCount $logA 'initialize') -eq 1)
Check 'stub saw didOpen once per file (2 files)' ((LogCount $logA 'textDocument/didOpen') -eq 2) "n=$(LogCount $logA 'textDocument/didOpen')"
Check 'stub saw n definition requests' ((LogCount $logA 'textDocument/definition') -eq $n) "n=$(LogCount $logA 'textDocument/definition')"
Check 'stub saw shutdown' ((LogCount $logA 'shutdown') -eq 1)
Check 'the child is gone when the verb exits (AC19)' (@(Get-Process LspStubServer -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$WorkDir*" }).Count -eq 0)

# --- (3) text mode of run A (AC12) --------------------------------------------------------
Write-Host ''
Write-Host '(3) text report' -ForegroundColor Cyan
$rt = Invoke-Verb (VerbArgs @()) $envA
$lines = @($rt.Out -split "`r?`n" | Where-Object { $_ -ne '' })
Check 'first line is the summary' ($lines.Count -ge 1 -and $lines[0] -match '^verify-index: db=.* sample=50 seed=1 match=\d+ mismatch=1 empty=0 error=0 skipped=0 rate=') $lines[0]
Check 'exactly one mismatch row' (@($lines | Where-Object { $_ -match '^mismatch\t' }).Count -eq 1)
Check 'text mode exits 1' ($rt.Code -eq 1)

# --- (4) run B: empty (retry), LocationLink, no answer, rest right (AC8, AC9, AC11, AC14) -------
Write-Host ''
Write-Host '(4) run B: empty retried once, LocationLink accepted, unanswered = error' -ForegroundColor Cyan
$ansB = @(for ($i = 0; $i -lt $n; $i++) {
  if ($i -eq 0) { 'null' }
  elseif ($i -eq 1) { '[{"targetUri":"' + (Uri $rows[1].dl.path) + '","targetRange":{"start":{"line":0,"character":0}},"targetSelectionRange":{"start":{"line":' + ($rows[1].dl.line - 1) + ',"character":0}}}]' }
  elseif ($i -eq 2) { $null }
  else { Right $rows[$i] }
})
$logB = Join-Path $WorkDir 'b.log'
$envB = @{ DRAGLINT_STUB_SCRIPT = (WriteScript 'b.script' $ansB); DRAGLINT_STUB_LOG = $logB }
$rb = Invoke-Verb (VerbArgs @('--json')) $envB
$jb = $null
try { $jb = $rb.Out | ConvertFrom-Json | ForEach-Object { $_ } } catch { }
Check 'run B exits 0 (no mismatch)' ($rb.Code -eq 0) "code=$($rb.Code) err=$($rb.Err)"
Check 'counts: empty 1, error 1, mismatch 0' ($jb -and $jb.counts.empty -eq 1 -and $jb.counts.error -eq 1 -and $jb.counts.mismatch -eq 0) $rb.Out
Check 'counts.match = n - 2 (LocationLink row matched)' ($jb -and $jb.counts.match -eq ($n - 2))
Check 'rate 0, empty kept out of the rate' ($jb -and $jb.rate -eq 0)
Check 'the empty row was asked twice (n + 1 definition requests)' ((LogCount $logB 'textDocument/definition') -eq ($n + 1)) "n=$(LogCount $logB 'textDocument/definition')"
Check 'rows lists the empty and the error row only' ($jb -and @($jb.rows).Count -eq 2 -and (@($jb.rows | ForEach-Object { $_.outcome }) -contains 'empty') -and (@($jb.rows | ForEach-Object { $_.outcome }) -contains 'error'))

# --- (5) errors (AC21) -------------------------------------------------------------------------
Write-Host ''
Write-Host '(5) setup errors: exit 2, ERROR on stderr, stdout empty' -ForegroundColor Cyan
$e1 = Invoke-Verb ($common + @('--delphi-lsp', $stub, '--delphi-lsp-config', (Join-Path $WorkDir 'nope.json')))
Check 'missing config -> exit 2' ($e1.Code -eq 2) "code=$($e1.Code)"
Check 'missing config -> ERROR: verify-index: on stderr, stdout empty' ($e1.Err -match 'ERROR: verify-index:' -and $e1.Out.Trim() -eq '') "err=$($e1.Err) out=$($e1.Out)"
$e2 = Invoke-Verb ($common + @('--delphi-lsp', 'C:\nonexistent\DelphiLSP.exe', '--delphi-lsp-config', $cfg))
Check 'missing DelphiLSP exe -> exit 2, stdout empty' ($e2.Code -eq 2 -and $e2.Err -match 'ERROR: verify-index:' -and $e2.Out.Trim() -eq '') "code=$($e2.Code) err=$($e2.Err)"
$nosett = Join-Path $WorkDir 'nosettings.delphilsp.json'
[IO.File]::WriteAllText($nosett, '{"other":1}', [Text.Encoding]::ASCII)
$e3 = Invoke-Verb ($common + @('--delphi-lsp', $stub, '--delphi-lsp-config', $nosett))
Check 'config without settings -> exit 2' ($e3.Code -eq 2 -and $e3.Err -match 'ERROR: verify-index:') "code=$($e3.Code) err=$($e3.Err)"
$e4 = Invoke-Verb @('verify-index', '--dry-run')
Check 'no --db and no --project -> exit 2' ($e4.Code -eq 2 -and $e4.Out.Trim() -eq '') "code=$($e4.Code) out=$($e4.Out) err=$($e4.Err)"

# --- (6) read-only (AC23) -----------------------------------------------------------------------
Write-Host ''
Write-Host '(6) read-only' -ForegroundColor Cyan
Check 'DB bytes unchanged across all runs' ((Get-FileHash $db -Algorithm SHA256).Hash -eq $sha0)

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
