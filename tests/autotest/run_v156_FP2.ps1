<#
  run_v156_FP2.ps1 -- v156 lane FP-2: duplicate-global-decl must not fire for a type ALIAS that re-exports
  the other unit's declaration (TAlias = uFp2B.TAlias is the same type, not a second one).

  Cases:
    TAlias   uFp2A: TAlias = uFp2B.TAlias;   uFp2B: TAlias = (aOne, aTwo);   -> NO finding
    TReal    uFp2A / uFp2B declare different arrays of one name              -> finding (positive control)
    TNear    uFp2A: TNear = uFp2C.TNear (names a unit that is not a site)    -> finding (alias to a third unit is not proof)
  Usage: pwsh -File tests\autotest\run_v156_FP2.ps1 [-Exe <engine>]
#>
[CmdletBinding()]
param([string]$Exe = '', [string]$WorkDir = '')
$ErrorActionPreference = 'Stop'
if (-not $Exe)     { $Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if (-not $WorkDir) { $WorkDir = "$env:TEMP\drag-lint-v156-fp2-$PID" }
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $(if ($Ok) { '' } else { $Detail })) -ForegroundColor $(if ($Ok) { 'Green' } else { 'Red' })
  if (-not $Ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  [IO.File]::WriteAllText($Path, ($Body -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$d = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $d | Out-Null
Write-Ascii (Join-Path $d 'uFp2A.pas') @'
unit uFp2A;
interface
uses uFp2B;
type
  TAlias = uFp2B.TAlias;
  TReal  = array [1..2] of Integer;
  TNear  = uFp2C.TNear;
implementation
end.
'@
Write-Ascii (Join-Path $d 'uFp2B.pas') @'
unit uFp2B;
interface
type
  TAlias = (aOne, aTwo);
  TReal  = array [1..9] of Integer;
  TNear  = (nOne, nTwo);
implementation
end.
'@
$db = Join-Path $WorkDir 'fp2.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $d --db $db --quiet 2>&1 | ForEach-Object { "$_" } } | Out-Null
Check 'scratch index built' (Test-Path $db)
$raw = & { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $db --json --quiet --library-db none 2>&1 | ForEach-Object { "$_" } }
$txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
$all = if ($b -ge 0) { @($txt.Substring($b) | ConvertFrom-Json | ForEach-Object { $_ }) } else { @() }
function Msg([string]$n) { (@($all | Where-Object { $_.rule -eq 'duplicate-global-decl' -and $_.message -match ('^' + [regex]::Escape($n) + '\b') } | ForEach-Object { $_.message }) -join ' | ') }
$m = @{}; foreach ($n in 'TAlias','TReal','TNear') { $m[$n] = Msg $n }
Check 'POSITIVE: TReal (two different declarations) still fires and says DIFFER' (($m.TReal -ne '') -and ($m.TReal -cmatch 'DECLARATIONS DIFFER')) $m.TReal
Check 'TNear (alias to a unit that is not the other site) still fires' ($m.TNear -ne '') $m.TNear
Check 'TAlias (re-export of the other unit declaration) does not fire' ($m.TAlias -eq '') $m.TAlias
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
