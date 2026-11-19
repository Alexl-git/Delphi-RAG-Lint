<#
  run_v1511_MARK_metric_algo_version.ps1 -- a routine-metric `dl:ok` survives an
  engine change in HOW the metric is measured, but not an edit of the routine
  (v1511 MARK, Y4 / INBOX-yadf-fp-hunt-151 FP-4).

  THE DEFECT: the marker hash was HashLine(header)|metric. When the engine's
  counting changed (1.47: deep-nesting counts ifElse; grammar v1.4.4 re-parsed
  if-with-else statements that cyclomatic/cognitive had skipped) every reviewed
  routine whose number moved went stale with no code change -- 10 of 10 in YADF.

  THE FIX (DRagLint.Lint.MarkerHash): a NEW marker's four hex digits are three of
  `header|metric|algorithm-version` plus one of `header|routine-body|version`.
  Same version + same metric -> verified (a metric-neutral body edit stays
  silent, as T3 run_marker_metric_scope.ps1 check 4 demands); metric moved under
  an OLDER version + body unchanged -> re-measured, suppressed, not stale; body
  edited -> stale. A legacy marker (header|metric) verifies exactly as before.

  DRAGLINT_TEST_METRIC_ALGO_BUMP=<rule>:+<n> simulates an algorithm change in the
  marker check only: current version + 1 and the measured value + n.

  RED on 1.51.0: check 6 (an edited body under an algorithm change is accepted,
  because the 1.51.0 hash ignores the body and the env hook does not exist).

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) ("draglint-algover-" + [Guid]::NewGuid().ToString('N')))
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
# H01-AUTOWRAP (v152 DDFIX5): the work dir is removed in the finally below; DL_KEEP_WORKDIR=1 keeps it.
. (Join-Path $PSScriptRoot 'lib\WorkDirCleanup.ps1')
try {
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}

Write-Host '== dl:ok on a routine metric: measure-algorithm version ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$pas = Join-Path $WorkDir 'uAlgoProbe.pas'
$db  = Join-Path $WorkDir 'probe.sqlite'
$HeaderLine = 7

function Probe([string]$Marker, [bool]$EditBody, [bool]$Deeper) {
  $hdr = 'procedure Deep(A, B, C, D, E, F, G: Boolean);'
  if ($Marker -ne '') { $hdr += '  // dl:ok deep-nesting@' + $Marker + ' -- probe' }
  $leaf = if ($EditBody) { 'Inc(N, 2)' } else { 'Inc(N)' }
  if ($Deeper) { $leaf = 'if G then ' + $leaf }
  @(
    'unit uAlgoProbe;'
    'interface'
    'procedure Deep(A, B, C, D, E, F, G: Boolean);'
    'implementation'
    'var N: Integer;'
    ''
    $hdr
    'begin'
    '  if A then'
    '    if B then'
    '      if C then'
    '        if D then'
    '          if E then'
    '            if F then'
    "              $leaf;"
    'end;'
    'end.'
  ) -join "`r`n" | Set-Content -LiteralPath $pas -Encoding ascii -NoNewline
}

function Lint([string]$Bump = '') {
  $old = $env:DRAGLINT_TEST_METRIC_ALGO_BUMP
  try {
    if ($Bump -ne '') { $env:DRAGLINT_TEST_METRIC_ALGO_BUMP = $Bump } else { [Environment]::SetEnvironmentVariable('DRAGLINT_TEST_METRIC_ALGO_BUMP', $null) }
    $out = & { $ErrorActionPreference = 'Continue'; & $Exe lint $pas --db $db --rule deep-nesting 2>$null } | Out-String
  } finally {
    if ($null -ne $old) { $env:DRAGLINT_TEST_METRIC_ALGO_BUMP = $old } else { [Environment]::SetEnvironmentVariable('DRAGLINT_TEST_METRIC_ALGO_BUMP', $null) }
  }
  [pscustomobject]@{
    Finding = $out -match '\[\w+\] deep-nesting:'
    Stale   = $out -match 'review-marker-stale'
    Want    = if ($out -match 'hashes to @([0-9a-f]{4})') { $Matches[1] } else { '' }
    Metric  = if ($out -match 'nests control structures (\d+) deep') { [int]$Matches[1] } else { -1 }
    Raw     = $out
  }
}

# The legacy (1.51.0) hash: sha256(normalized header|metric), first four hex.
function LegacyHash([int]$Metric) {
  $norm = ('procedure Deep(A, B, C, D, E, F, G: Boolean);' -replace '[ \t]', '').ToLower()
  $sha = [Security.Cryptography.SHA256]::Create()
  $h1 = ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($norm)) | ForEach-Object { $_.ToString('x2') }) -join ''
  $h2 = ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($h1.Substring(0, 4) + '|' + $Metric)) | ForEach-Object { $_.ToString('x2') }) -join ''
  $h2.Substring(0, 4)
}

Probe '' $false $false
& { $ErrorActionPreference = 'Continue'; & $Exe index $WorkDir --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null

# 1. positive control: the rule fires on the probe.
$r = Lint
Check '1 deep-nesting fires on the unmarked probe' ($r.Finding -and $r.Metric -eq 6) "metric=$($r.Metric)"

# 2. the engine's own expected hash, read from the stale hint of a wrong marker.
Probe '0001' $false $false
$r = Lint
$Want = $r.Want
Check '2 a wrong marker is stale and names the expected hash' ($r.Stale -and $Want -ne '') "want=$Want"

# 3. a marker carrying that hash verifies.
Probe $Want $false $false
$r = Lint
Check '3 the expected hash verifies' ((-not $r.Finding) -and (-not $r.Stale))

# 4. T3 kept: a body edit that does not move the metric stays silent.
Probe $Want $true $false
$r = Lint
Check '4 metric-neutral body edit stays verified (T3)' ((-not $r.Finding) -and (-not $r.Stale))

# 5. growth under the SAME algorithm re-opens.
Probe $Want $false $true
$r = Lint
Check '5 metric growth under the same algorithm is stale' ($r.Stale) "metric=$($r.Metric)"

# 6. POSITIVE CONTROL for the re-measure: an algorithm change plus an EDITED body is stale.
Probe $Want $true $false
$r = Lint 'deep-nesting:+1'
Check '6 algorithm change + edited body -> stale' ($r.Stale)

# 7. an algorithm change on an UNCHANGED body is re-measured: suppressed, not stale.
Probe $Want $false $false
$r = Lint 'deep-nesting:+1'
Check '7 algorithm change + unchanged body -> re-measured, not stale' ((-not $r.Finding) -and (-not $r.Stale))

# 8. an OLD marker (1.51.0 hash) keeps verifying -- no mass re-stamp.
Probe (LegacyHash 6) $false $false
$r = Lint
Check '8 legacy marker verifies as before' ((-not $r.Finding) -and (-not $r.Stale)) "legacy=$(LegacyHash 6)"

# 9. ...and a legacy marker still goes stale when the metric grows.
Probe (LegacyHash 6) $false $true
$r = Lint
Check '9 legacy marker + growth -> stale' ($r.Stale)

if ($script:Failed) { Write-Host "FAIL (work dir kept: $WorkDir)" -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally { Remove-WorkDir $WorkDir -Keep:($env:DL_KEEP_WORKDIR -eq '1') }
