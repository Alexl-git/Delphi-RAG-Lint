#Requires -Version 7.3
<#
  run_v152_BK-TOOLING2.ps1 -- 1.52 lane BK-TOOLING2 (backlog B25 + B26).

  B26: the five pre-existing near-duplicate --help line pairs (a frozen block plus the blockless
       surface of a second entry) are merged into one registry surface each, so the generated verb
       reference (src\cli\DRagLint.CLI.HelpText.pas, WriteVerbReference) prints ONE line per pair
       and run_docs_sync_guard.ps1 no longer lists them in $DuplicateHelpOnPurpose.
  B25: featuregen's subcommand harvest follows Args.SubCommand into a routine's first parameter
       (repo -> RunRepoVerb(pSub, ...)) and MatchText(Args.SubCommand, [...]) arms (rules
       disable|enable), so those sub-verbs are registered as per-sub cli surfaces.
       The harvest itself is unit-tested in FeatureGenTests (Live.SubParam.*); with -Engine this
       runner also runs `featuregen check --level full` and requires no subcommand failure.

  Exit 0 = every check passed.
#>
[CmdletBinding()]
param([string]$Repo = '',
      [string]$Engine = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
$ErrorActionPreference = 'Stop'
$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "[PASS] $Name $Detail" }
  else     { $script:fail++; Write-Host "[FAIL] $Name $Detail" -ForegroundColor Red }
}

# --- B26: one verb-reference line per formerly duplicated pair -------------------------------
$unit = [IO.File]::ReadAllText((Join-Path $Repo 'src\cli\DRagLint.CLI.HelpText.pas'))
$m = [regex]::Match($unit, '(?ms)^procedure WriteVerbReference;.*?^end;')
Check 'B26 WriteVerbReference found in the generated unit' $m.Success
$keys = @('document --qname', 'extract-method --in', 'format <file>', 'reverse-calltree --qname', 'rules [--json]')
foreach ($k in $keys) {
  $rx = "Writeln\('  drag-lint " + [regex]::Escape($k)
  $n = [regex]::Matches($m.Value, $rx).Count
  Check "B26 one verb-reference line for '$k'" ($n -eq 1) "(found $n)"
}
$guard = [IO.File]::ReadAllText((Join-Path $Repo 'tests\autotest\run_docs_sync_guard.ps1'))
foreach ($k in $keys) {
  Check "B26 '$k' no longer in DuplicateHelpOnPurpose" (-not $guard.Contains("'$k'"))
}

# --- B25: sub-verbs dispatched through a routine parameter are registered per sub --------------
function Get-CliSubs([string]$Verb) {
  $subs = @()
  foreach ($f in Get-ChildItem (Join-Path $Repo 'features\entries') -Filter *.json) {
    $j = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
    foreach ($s in @($j.surfaces)) {
      if (($s.type -eq 'cli') -and ($s.verb -eq $Verb) -and $s.sub) { $subs += $s.sub }
    }
  }
  , @($subs | Sort-Object -Unique)
}
$repoSrc = [IO.File]::ReadAllText((Join-Path $Repo 'src\cli\DRagLint.CLI.Repo.pas'))
$im = [regex]::Match($repoSrc, '(?s)function IsImplementedSub\(.*?MatchText\(pSub, \[(.*?)\]\)')
$want = @([regex]::Matches($im.Groups[1].Value, "'([a-z0-9-]+)'") | ForEach-Object { $_.Groups[1].Value }) + @('gen-param-array')
Check 'B25 control: IsImplementedSub lists the repo sub-verbs' ($want.Count -ge 10) "($($want.Count))"
$have = Get-CliSubs 'repo'
$missing = @($want | Where-Object { $have -notcontains $_ })
Check 'B25 every repo sub-verb has a cli surface with sub' ($missing.Count -eq 0) $(if ($missing) { "missing: $($missing -join ', ')" } else { "($($have.Count))" })
$rules = Get-CliSubs 'rules'
Check 'B25 rules disable + enable have cli surfaces with sub' ((@($rules) -contains 'disable') -and (@($rules) -contains 'enable')) "($($rules -join ', '))"
$t = [IO.File]::ReadAllText((Join-Path $Repo 'src\tools\featuregen\tests\FeatureGenTests.dpr'))
Check 'B25 FeatureGenTests runs the sub-parameter harvest test' ($t -match '(?m)^\s+TestHarvestSubParamRoutines;')

if ($Engine) {
  $fg = Join-Path $Repo 'src\tools\featuregen\featuregen.exe'
  $out = & $fg check --level full --repo $Repo --engine $Engine 2>&1 | Out-String
  $subFails = @($out -split "`n" | Where-Object { $_ -match 'subcommand' -and $_ -match '^\s*[BC]:' })
  Check 'B25 featuregen check full: no subcommand failure' ($subFails.Count -eq 0) ($subFails -join ' | ')
}

Write-Host "SUMMARY pass=$($script:pass) fail=$($script:fail)"
if ($script:fail -gt 0) { exit 1 }
exit 0
