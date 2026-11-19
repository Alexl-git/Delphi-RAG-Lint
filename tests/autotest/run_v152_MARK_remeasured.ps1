<#
  run_v152_MARK_remeasured.ps1 -- hint `review-marker-remeasured` (v152 MARK, ruling B3).

  A routine-metric `dl:ok` that was stamped under an older hash (the 1.51.0 "v1"
  header|metric hash) or an older measure-algorithm version and is STILL valid under
  the v2 hash is today accepted in silence. The owner wants to be told: one hint,
  default ON, severity hint, naming the marker and the re-stamp command. The finding
  stays suppressed; a marker that really went stale keeps reporting
  review-marker-stale and gets NO remeasured hint.

  Checks (probe = a 6-deep deep-nesting routine, see run_v1511_MARK_metric_algo_version.ps1):
    1 positive control: the rule fires on the unmarked probe
    2 the engine's own v2 hash is read from the stale hint of a wrong marker
    3 a current v2 marker -> verified: finding suppressed, NO hint (control for the 4/6 hint counts)
    4 a legacy (v1) marker on unchanged code -> suppressed, exactly ONE remeasured hint
    5 a legacy marker + metric growth -> review-marker-stale, no remeasured hint
    6 v2 marker + simulated algorithm bump + unchanged body -> suppressed, exactly ONE hint
    7 v2 marker + algorithm bump + EDITED body -> review-marker-stale, no remeasured hint
    8 the hint names the rule and the re-stamp command (allow --fix-line)

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) ("draglint-remeasured-" + [Guid]::NewGuid().ToString('N')))
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}

Write-Host '== dl:ok re-measured under the v2 hash: hint review-marker-remeasured ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$pas = Join-Path $WorkDir 'uRemeasProbe.pas'
$db  = Join-Path $WorkDir 'probe.sqlite'

function Probe([string]$Marker, [bool]$EditBody, [bool]$Deeper) {
  $hdr = 'procedure Deep(A, B, C, D, E, F, G: Boolean);'
  if ($Marker -ne '') { $hdr += '  // dl:ok deep-nesting@' + $Marker + ' -- probe' }
  $leaf = if ($EditBody) { 'Inc(N, 2)' } else { 'Inc(N)' }
  if ($Deeper) { $leaf = 'if G then ' + $leaf }
  @(
    'unit uRemeasProbe;'
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
    Remeas  = ([regex]::Matches($out, 'review-marker-remeasured')).Count
    Want    = if ($out -match 'hashes to @([0-9a-f]{4})') { $Matches[1] } else { '' }
    Raw     = $out
  }
}

# The legacy (1.51.0 / v1) hash: sha256(normalized header|metric), first four hex.
function LegacyHash([int]$Metric) {
  $norm = ('procedure Deep(A, B, C, D, E, F, G: Boolean);' -replace '[ \t]', '').ToLower()
  $sha = [Security.Cryptography.SHA256]::Create()
  $h1 = ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($norm)) | ForEach-Object { $_.ToString('x2') }) -join ''
  $h2 = ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($h1.Substring(0, 4) + '|' + $Metric)) | ForEach-Object { $_.ToString('x2') }) -join ''
  $h2.Substring(0, 4)
}

Probe '' $false $false
& { $ErrorActionPreference = 'Continue'; & $Exe index $WorkDir --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null

$r = Lint
Check '1 deep-nesting fires on the unmarked probe' $r.Finding

Probe '0001' $false $false
$r = Lint
$Want = $r.Want
Check '2 a wrong marker is stale and names the v2 hash' ($r.Stale -and $Want -ne '') "want=$Want"

Probe $Want $false $false
$r = Lint
Check '3 a current v2 marker: suppressed, no stale, no remeasured hint' ((-not $r.Finding) -and (-not $r.Stale) -and ($r.Remeas -eq 0))

$Legacy = LegacyHash 6
Probe $Legacy $false $false
$r = Lint
# positive-control: review-marker-remeasured
Check '4 legacy (v1) marker, unchanged code: suppressed + exactly one hint' ((-not $r.Finding) -and (-not $r.Stale) -and ($r.Remeas -eq 1)) "hints=$($r.Remeas)"
$Msg = $r.Raw
Check '8 the hint names the rule and the re-stamp command' (($Msg -match 'deep-nesting') -and ($Msg -match 'allow --fix-line'))

Probe $Legacy $false $true
$r = Lint
Check '5 legacy marker + growth: stale, no remeasured hint' ($r.Stale -and ($r.Remeas -eq 0))

Probe $Want $false $false
$r = Lint 'deep-nesting:+1'
Check '6 v2 marker + algorithm bump + unchanged body: suppressed + exactly one hint' ((-not $r.Finding) -and (-not $r.Stale) -and ($r.Remeas -eq 1)) "hints=$($r.Remeas)"

Probe $Want $true $false
$r = Lint 'deep-nesting:+1'
Check '7 v2 marker + algorithm bump + edited body: stale, no remeasured hint' ($r.Stale -and ($r.Remeas -eq 0))

if ($script:Failed) { Write-Host "FAIL (work dir kept: $WorkDir)" -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0