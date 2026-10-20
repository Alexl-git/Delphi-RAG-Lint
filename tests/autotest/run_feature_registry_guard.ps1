#Requires -Version 7.3
<#
  run_feature_registry_guard.ps1 -- every live surface has a registry entry and every
  entry points at something that exists; the generated pages are current and untouched.
  Spec section 9. Since the 2026-10 cut-over the checks live in featuregen.exe
  (src\tools\featuregen); this runner is the battery's door to them.

  A  well-formed (schema, canonical bytes, groups/teams, references, ASCII+CRLF)
  B  live -> registry: every --help verb, subcommand, IDE caption, MCP tool, rule,
     chart question and release exe is registered or exempted WITH a reason
  C  registry -> live: every cli / ide-* / tool-window / mcp surface is live
  D  every generated output is byte-identical to a fresh render: the four wiki
     pages, the two dl:registry blocks, manifest.json, cli-reference.md, the
     website set (WWW\help\dl) and site-pages.json
  E  staleness is a [NOTE], never a FAIL (the periodic review consumes it)

  This runner executes  featuregen check --level full  and  featuregen build --all --check
  on the real repo. A MISSING featuregen.exe or engine is "GUARD BROKEN" (exit 1), never a
  pass. Before the real run it proves, on a scratch copy of the registry, that the tool goes
  RED on a seeded defect and green on the unseeded copy (the positive control); the
  injected-verb / caption / MCP-tool / hand-edit controls for B, C and D live in
  src\tools\featuregen\tests\FeatureGenTests.dpr (run by run_featuregen_tests.ps1).

  Parameters:
    -Repo     repo root (default: two levels above this script)
    -WorkDir  scratch folder for the control (created, removed on exit; unique per process)
#>
[CmdletBinding()]
param([string]$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path,
      [string]$WorkDir = "$env:TEMP\drag-lint-feature-registry-guard-$PID")
Set-StrictMode -Version Latest
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
Write-Host '== feature registry guard (featuregen) ==' -ForegroundColor Cyan
$exe = if ($env:FEATUREGEN_EXE) { $env:FEATUREGEN_EXE } else { Join-Path $Repo 'src\tools\featuregen\featuregen.exe' }
$engine = Join-Path $Repo 'third_party\dll-win64\drag-lint.exe'
if (-not (Test-Path -LiteralPath $exe)) { Write-Host "GUARD BROKEN: featuregen.exe not found: $exe (build\_build_featuregen_local.bat builds it)" -ForegroundColor Red; exit 1 }
if (-not (Test-Path -LiteralPath $engine)) { Write-Host "GUARD BROKEN: engine not found: $engine" -ForegroundColor Red; exit 1 }
if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path $WorkDir | Out-Null

# ---- control first: the tool goes red on a seeded defect, green without it ------------
Write-Host '-- control' -ForegroundColor Cyan
$scratch = Join-Path $WorkDir 'repo'
New-Item -ItemType Directory -Path $scratch | Out-Null
foreach ($d in 'features', 'docs\wiki', 'tools') {
  New-Item -ItemType Directory -Path (Split-Path -Parent (Join-Path $scratch $d)) -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $Repo $d) -Destination (Join-Path $scratch $d) -Recurse
}
Copy-Item -LiteralPath (Join-Path $Repo 'CHANGELOG.md') -Destination $scratch
New-Item -ItemType Directory -Path (Join-Path $scratch 'charts') | Out-Null
Copy-Item -LiteralPath (Join-Path $Repo 'charts\README.md') -Destination (Join-Path $scratch 'charts\README.md')
$clean = & $exe check --level wellformed --repo $scratch 2>&1 | Out-String
$cleanExit = $LASTEXITCODE
if ($cleanExit -ne 0) { Write-Host "GUARD BROKEN: the unseeded scratch copy does not pass check A (exit $cleanExit): $($clean.Trim())" -ForegroundColor Red; exit 1 }
$seed = Join-Path $scratch 'features\entries\zz-guard-control.json'
[IO.File]::WriteAllText($seed, "{`r`n  `"id`": `"zz-guard-control`",`r`n  `"zzUnknownKey`": 1`r`n}`r`n", [Text.Encoding]::ASCII)
$red = & $exe check --level wellformed --repo $scratch 2>&1 | Out-String
if (($LASTEXITCODE -ne 1) -or ($red -notmatch 'zz-guard-control\.json')) { Write-Host "GUARD BROKEN: a seeded bad entry did not fail check A naming it (exit $LASTEXITCODE): $($red.Trim())" -ForegroundColor Red; exit 1 }
Write-Host '  [CTRL] a seeded bad entry fails check A and is named; the unseeded copy passes' -ForegroundColor DarkGray

# ---- the real repo ----------------------------------------------------------------------
Write-Host '-- checks A-E (check --level full)' -ForegroundColor Cyan
$out = & $exe check --level full --repo $Repo --engine $engine 2>&1 | Out-String
$code = $LASTEXITCODE
Check 'registry check A-E: no failures' ($code -eq 0) "(exit $code)"
if ($code -ne 0) { Write-Host ($out.TrimEnd() -replace '(?m)^', '    ') -ForegroundColor Red }
Write-Host '-- generated outputs current (build --all --check)' -ForegroundColor Cyan
$out = & $exe build --all --check --repo $Repo --engine $engine 2>&1 | Out-String
$code = $LASTEXITCODE
Check 'every generated output is current' ($code -eq 0) "(exit $code)"
if ($code -ne 0) { Write-Host ($out.TrimEnd() -replace '(?m)^', '    ') -ForegroundColor Red }

Write-Host ''
if ($script:Failed) { Write-Host 'FEATURE REGISTRY GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'FEATURE REGISTRY GUARD: PASS' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
