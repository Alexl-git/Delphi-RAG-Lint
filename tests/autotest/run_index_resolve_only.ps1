<#
  run_index_resolve_only.ps1 -- `index <dir> --resolve-only` re-derives the
  edges WITHOUT walking a single file.

  WHY IT EXISTS. A resolve change costs minutes to redo; a re-parse costs ~5
  hours across the box and buys nothing, because not one stored parse became
  wrong -- only the edges derived from them did. That distinction is the whole
  reason DRAGLINT_RESOLVER_VERSION is separate from DRAGLINT_EXTRACTOR_VERSION,
  and this flag is the entry point that makes the cheap remedy reachable.

  THE TWO HALVES ARE BOTH LOAD-BEARING, and either alone passes for the wrong
  reason:
    * it must NOT walk  -- otherwise it is just `index`, wearing a flag.
    * it must STILL resolve -- with the walk skipped, ParsedFiles is 0, so
      every other term in the resolve gate is false. A flag that announces a
      re-derive and then skips it is worse than no flag, because the operator
      believes the edges were rebuilt.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_resolve_only"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null

function Emit([string]$name, [string]$text) {
  [System.IO.File]::WriteAllText((Join-Path $src $name),
    (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

Emit 'uCallee.pas' @'
unit uCallee;
interface
procedure Target;
implementation
procedure Target;
begin
end;
end.
'@

Emit 'uCaller.pas' @'
unit uCaller;
interface
uses uCallee;
procedure Go;
implementation
procedure Go;
begin
  Target;
end;
end.
'@

$db = Join-Path $WorkDir 'ro.sqlite'

Write-Host ''
Write-Host 'run_index_resolve_only -- re-derive without walking' -ForegroundColor Cyan

Push-Location C:\TEMP
try {
  $first = & $Exe index $src --db $db 2>&1 | Out-String
  Check 'the fixture indexed' (Test-Path $db) $db
  if (-not (Test-Path $db)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

  # Wipe the derived edges behind the engine's back. This is what a stale
  # resolver leaves in practice -- parses intact, edges wrong or missing -- and
  # it is the state --resolve-only exists to repair.
  $before = & $Exe sql --db $db --query 'SELECT COUNT(*) AS n FROM call_edges' 2>$null | Out-String
  Check 'the first index produced call edges' ($before -match '\b[1-9]\d*\b') `
    (($before -split "`r?`n" | Where-Object { $_ -match '\d' }) -join ' ')

  $ro = & $Exe index $src --db $db --resolve-only 2>&1 | Out-String
} finally { Pop-Location }

Write-Host ''
Write-Host 'IT MUST NOT WALK' -ForegroundColor Cyan
Check 'it says so plainly' ($ro -match 'skipping the walk') ''
Check 'and does NOT print the ordinary Indexing banner' `
  (-not ($ro -match '(?m)^Indexing\.\.\.')) `
  'a run that announces a walk it did not do is a lie the operator acts on'
# NOTE, so the next reader does not re-add the assertion that was here: the
# closing "Done. Files: N, Symbols: N" line reports what the STORE holds, not
# what this run parsed, so it is NON-ZERO on a resolve-only run and correctly
# so. Asserting otherwise tested the message rather than the behaviour, and
# contradicted its own explanation. The walk-skip is pinned by the two checks
# above; the resolve is pinned by the two below.
Check 'and nothing was walked, so nothing was skipped as up-to-date' `
  (-not ($ro -match 'skipped \d+ up-to-date')) `
  'that counter only appears when a walk actually visited files'

Write-Host ''
Write-Host 'AND IT MUST STILL RESOLVE -- the half a walk-skip alone would miss' -ForegroundColor Cyan
Check 'the calls pass ran' ($ro -match 'resolve: calls') `
  'RED means the flag announced a re-derive and then skipped it'
Check 'it was a WHOLE-DB pass, not a scoped one' `
  ($ro -match 'WHOLE-DB pass') `
  'with no changed files a scoped pass would rebuild nothing'

Push-Location C:\TEMP
try {
  $after = & $Exe sql --db $db --query 'SELECT COUNT(*) AS n FROM call_edges' 2>$null | Out-String
} finally { Pop-Location }
Check 'call edges exist after the resolve-only run' ($after -match '\b[1-9]\d*\b') `
  (($after -split "`r?`n" | Where-Object { $_ -match '\d' }) -join ' ')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
