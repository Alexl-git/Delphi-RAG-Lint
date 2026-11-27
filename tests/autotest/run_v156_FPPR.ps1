<#
  run_v156_FPPR.ps1 -- v156 lane FP-PR: unused-unit-in-uses no longer reports a unit used only
  through an attribute or needed only for inline expansion (H2443).

  Fixture tests\fixtures\v156\FPPR (one finding expected per case on the base engine):
    uFpprShort          [Inject]                          keeps Spring.Container.Common (InjectAttribute)
    uFpprQual           [Spring.Container.Common.Inject]  keeps Spring.Container.Common
    uFpprCallBody       MidColl.Touch, inline, body calls uFpprLeaf.LeafValue     keeps uFpprLeaf
    uFpprCallInherited  MidColl[1], inline default accessor reaching its ancestor keeps uFpprBase
  Positive controls (must STILL fire):
    uFpprCallPlain      uFpprDead: nothing of it is used
    uFpprCallPlain      uFpprOther: reached only by the NON-inline TMidColl.Plain (dcc needs no unit for it)
  Usage: pwsh -File tests\autotest\run_v156_FPPR.ps1 [-Exe <engine>]
#>
[CmdletBinding()]
param([string]$Exe = '', [string]$WorkDir = '')
$ErrorActionPreference = 'Stop'
if (-not $Exe)     { $Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if (-not $WorkDir) { $WorkDir = "$env:TEMP\drag-lint-v156-fppr-$PID" }
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $(if ($Ok) { '' } else { $Detail })) -ForegroundColor $(if ($Ok) { 'Green' } else { 'Red' })
  if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$fx  = (Resolve-Path "$PSScriptRoot\..\fixtures\v156\FPPR").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$db = Join-Path $WorkDir 'fppr.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $fx --db $db --quiet 2>&1 | ForEach-Object { "$_" } } | Out-Null
Check 'scratch index built' (Test-Path $db)
$raw = & { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $db --json --quiet --library-db none --rule unused-unit-in-uses 2>&1 | ForEach-Object { "$_" } }
$txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
$all = if ($b -ge 0) { @($txt.Substring($b) | ConvertFrom-Json | ForEach-Object { $_ }) } else { @() }
$uu  = @($all | Where-Object { $_.rule -eq 'unused-unit-in-uses' })
# One "file|unit" key per finding; the unit is the quoted name the message opens with.
$keys = @($uu | ForEach-Object { '{0}|{1}' -f [IO.Path]::GetFileNameWithoutExtension("$($_.file_path)"), $(if ("$($_.message)" -match "^Unit '([^']+)'") { $Matches[1] } else { '?' }) })
function Fires([string]$File, [string]$Unit) { return ($keys -contains "$File|$Unit") }
$shape = ($keys -join ', ')
Check 'the JSON carries file + message (the keys are readable)' (($keys.Count -gt 0) -and -not (@($keys | Where-Object { $_ -match '^\||\|\?$' }).Count)) $shape
Check 'POSITIVE: a really unused unit still fires (uFpprCallPlain / uFpprDead)' (Fires 'uFpprCallPlain' 'uFpprDead') $shape
Check 'POSITIVE: a unit reached only by a NON-inline routine still fires (uFpprCallPlain / uFpprOther)' (Fires 'uFpprCallPlain' 'uFpprOther') $shape
Check '[Inject] keeps the unit of InjectAttribute (uFpprShort)' (-not (Fires 'uFpprShort' 'Spring.Container.Common')) $shape
Check '[Spring.Container.Common.Inject] keeps the unit (uFpprQual)' (-not (Fires 'uFpprQual' 'Spring.Container.Common')) $shape
Check 'inline body reaches the unit: uFpprLeaf kept (uFpprCallBody)' (-not (Fires 'uFpprCallBody' 'uFpprLeaf')) $shape
Check 'inline default accessor reaches its ancestor unit: uFpprBase kept (uFpprCallInherited)' (-not (Fires 'uFpprCallInherited' 'uFpprBase')) $shape
Check 'exactly the two controls remain' ($keys.Count -eq 2) $shape
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
