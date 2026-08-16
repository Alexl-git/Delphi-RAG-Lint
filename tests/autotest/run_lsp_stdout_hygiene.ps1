<#
  run_lsp_stdout_hygiene.ps1 -- nothing on the `lsp` / `serve` failure paths may
  write to STDOUT, because for those two commands stdout IS the JSON-RPC
  transport.

  THE DEFECT THIS PINS:
    DRagLint.CLI.Run's catch-all was a bare `Writeln('FATAL: ', ...)`. Under
    `lsp` that put the only line explaining the server's death into the wire
    where a Content-Length header belongs. The client discarded it, reported
    `write EPIPE`, restarted five times in three minutes, and latched
    vscode-languageclient's circuit breaker -- so the user's symptom was not
    "drag-lint hiccuped" but "drag-lint has no hovers today", with no diagnostic
    anywhere and no recovery short of reloading the window.

    The `lsp` branch already carried the invariant as a COMMENT --
    "Writes to ErrOutput only -- must NOT pollute the JSON-RPC stdout stream" --
    and was violated about sixty lines below it. That is the signature of a rule
    that lives only in prose, so this file makes it executable.

  Two layers, because either alone is weak:
    1. STATIC -- scan the source of `Run` and require that every Writeln in it
       is either ErrOutput-directed or on the explicit allow-list. The
       allow-list exists so the check cannot be satisfied by deleting output;
       adding to it is a deliberate act with a reason attached.
    2. BEHAVIOURAL -- actually run `drag-lint lsp --db` (a trailing bare --db
       fatals during argument parsing, the cheapest real fatal on this path) and
       require the FATAL text on stderr with stdout EMPTY. A static check alone
       would pass if the message moved to some other stdout-bound helper.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$Source  = "$PSScriptRoot\..\..\src\cli\DRagLint.CLI.pas",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-stdout-hygiene"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe))    { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $Source)) { Write-Host "FATAL: source not found: $Source" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

# ---------- layer 1: static scan of Run ----------
Write-Host 'STATIC: no bare Writeln on a path `lsp`/`serve` can reach' -ForegroundColor Cyan
$lines = Get-Content $Source
# `Run` is the LAST 'function Run: Integer;' in the unit -- the first is the
# interface declaration. Take the implementation and read to the unit's end.
# Regex, NOT -SimpleMatch: -SimpleMatch would treat the '^' anchor as a literal
# character and match nothing.
$runStarts = @($lines | Select-String -Pattern '^function Run: Integer;')
Check 'found the Run implementation' ($runStarts.Count -ge 2) "matches=$($runStarts.Count)"
if ($runStarts.Count -lt 2) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
$runFrom = $runStarts[-1].LineNumber
$body = $lines[($runFrom - 1)..($lines.Count - 1)]

# Writes that are legitimately stdout: they belong to a COMMAND'S OUTPUT, and
# none of them is reachable while stdout is a protocol stream. Keep this list
# short and justified -- it is the escape hatch, so it is also the thing to
# review when this test is edited.
$allow = @(
  "Writeln('drag-lint ', VERSION)"   # `--version`: its output IS stdout, and Args.Command is not lsp/serve
)
$offenders = @()
for ($i = 0; $i -lt $body.Count; $i++) {
  $ln = $body[$i]
  if ($ln -notmatch 'Writeln\(') { continue }
  if ($ln -match 'Writeln\(\s*ErrOutput') { continue }
  $ok = $false
  foreach ($a in $allow) { if ($ln.Contains($a)) { $ok = $true; break } }
  if (-not $ok) { $offenders += ("{0}: {1}" -f ($runFrom + $i), $ln.Trim()) }
}
Check 'every Writeln in Run is ErrOutput or allow-listed' ($offenders.Count -eq 0) `
  ($(if ($offenders.Count) { "`n        " + ($offenders -join "`n        ") } else { '' }))

# Guard the guard: if the allow-listed line ever disappears, the scan above is
# passing over an empty set and proves nothing.
$sawAllowed = $false
foreach ($ln in $body) { foreach ($a in $allow) { if ($ln.Contains($a)) { $sawAllowed = $true } } }
Check 'the allow-listed write still exists (scan is not vacuous)' $sawAllowed

# The two specific lines this defect was in, asserted by content rather than by
# line number so a shifted file does not silently stop checking them.
$joined = ($body -join "`n")
Check 'the FATAL catch-all writes to ErrOutput' `
  ($joined -match "Writeln\(\s*ErrOutput,\s*'FATAL: '") ''
Check 'the unknown-command branch writes to ErrOutput' `
  ($joined -match "Writeln\(\s*ErrOutput,\s*'ERROR: unknown command: '") ''

# ---------- layer 2: behavioural ----------
Write-Host ''
Write-Host 'BEHAVIOURAL: a real fatal on the lsp path keeps stdout clean' -ForegroundColor Cyan
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$init = Join-Path $WorkDir 'init.txt'
$body2 = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":null,"capabilities":{}}}'
[System.IO.File]::WriteAllText($init, "Content-Length: $($body2.Length)`r`n`r`n$body2", [System.Text.Encoding]::ASCII)
$so = Join-Path $WorkDir 'out.txt'
$se = Join-Path $WorkDir 'err.txt'

# A TRAILING BARE --db fatals in argument parsing, before the first store opens.
# This is the exact reproduction from the incident report, and it is also the
# live foot-gun the VS Code client has: it builds args as
# `['lsp']` then pushes '--db', <value> per configured database, so an EMPTY
# STRING in dragLint.databases produces precisely this command line.
$p = Start-Process $Exe -ArgumentList 'lsp','--db' -WorkingDirectory $WorkDir `
       -RedirectStandardInput $init -RedirectStandardOutput $so -RedirectStandardError $se `
       -NoNewWindow -Wait -PassThru
$out = (Get-Content $so -Raw); if ($null -eq $out) { $out = '' }
$err = (Get-Content $se -Raw); if ($null -eq $err) { $err = '' }

Check 'exit code is still 3 (behaviour unchanged, only the channel moved)' ($p.ExitCode -eq 3) "exit=$($p.ExitCode)"
Check 'STDOUT is empty -- nothing was injected into the JSON-RPC stream' ($out.Trim() -eq '') `
  ("stdout=" + $out.Trim())
Check 'STDERR carries the FATAL, so the client channel can show it' ($err -match 'FATAL:') `
  (($err -split "`r?`n" | Where-Object { $_ -match 'FATAL:' } | Select-Object -First 1))

# The breadcrumb: a transient fatal has to remain diagnosable after the
# transport is gone.
$crumb = Join-Path (Split-Path $Exe) 'drag-lint-fatal.log'
Check 'a fatal breadcrumb was appended beside the exe' (Test-Path $crumb) "path=$crumb"
if (Test-Path $crumb) {
  $tail = Get-Content $crumb -Tail 1
  Check 'the breadcrumb names the command and the exception' `
    ($tail -match 'cmd=lsp' -and $tail -match 'Exception') $tail
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
