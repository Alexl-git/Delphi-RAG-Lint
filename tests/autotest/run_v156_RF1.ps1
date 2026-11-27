<#
  run_v156_RF1.ps1 -- v156 lane RF-1 (owner Q28): duplicate-global-decl compares the types a declaration NAMES, one level deep.

  Cases (each a pair of units declaring the same names):
    TLeafDiff / THoldDiff   leaf differs (1..2 vs 1..9); the hold text is equal  -> hold says DECLARATIONS DIFFER
    TLeafSame / THoldSame   leaf identical in both units                          -> hold says identical, not NOT compared
    THoldGone               names a type declared nowhere                         -> still NOT compared (positive control)
    TPlain                  builtin element type, same text                       -> identical (positive control: a real duplicate fires)
  Usage: pwsh -File tests\autotest\run_v156_RF1.ps1 [-Exe <engine>]
#>
[CmdletBinding()]
param([string]$Exe = '', [string]$WorkDir = '')
$ErrorActionPreference = 'Stop'
if (-not $Exe)     { $Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if (-not $WorkDir) { $WorkDir = "$env:TEMP\drag-lint-v156-rf1-$PID" }
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
Write-Ascii (Join-Path $d 'uRf1A.pas') @'
unit uRf1A;
interface
type
  TLeafDiff = array [1..2] of Integer;
  THoldDiff = array [1..3] of TLeafDiff;
  TLeafSame = array [1..2] of Integer;
  THoldSame = array [1..3] of TLeafSame;
  THoldGone = array [1..3] of TNowhereDeclared;
  TPlain    = array [1..3] of Integer;
implementation
end.
'@
Write-Ascii (Join-Path $d 'uRf1B.pas') @'
unit uRf1B;
interface
type
  TLeafDiff = array [1..9] of Integer;
  THoldDiff = array [1..3] of TLeafDiff;
  TLeafSame = array [1..2] of Integer;
  THoldSame = array [1..3] of TLeafSame;
  THoldGone = array [1..3] of TNowhereDeclared;
  TPlain    = array [1..3] of Integer;
implementation
end.
'@
$db = Join-Path $WorkDir 'rf1.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $d --db $db --quiet 2>&1 | ForEach-Object { "$_" } } | Out-Null
Check 'scratch index built' (Test-Path $db)
$raw = & { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $db --json --quiet --library-db none 2>&1 | ForEach-Object { "$_" } }
$txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
$all = if ($b -ge 0) { @($txt.Substring($b) | ConvertFrom-Json | ForEach-Object { $_ }) } else { @() }
function Msg([string]$n) { (@($all | Where-Object { $_.rule -eq 'duplicate-global-decl' -and $_.message -match ('^' + [regex]::Escape($n) + '\b') } | ForEach-Object { $_.message }) -join ' | ') }
$m = @{}; foreach ($n in 'TLeafDiff','THoldDiff','TLeafSame','THoldSame','THoldGone','TPlain') { $m[$n] = Msg $n }
Check 'POSITIVE: TPlain (a real duplicate) still fires and says identical' (($m.TPlain -match 'identical,') -and ($m.TPlain -cnotmatch 'NOT compared')) $m.TPlain
Check 'TLeafDiff itself says DECLARATIONS DIFFER' ($m.TLeafDiff -cmatch 'DECLARATIONS DIFFER') $m.TLeafDiff
Check 'THoldDiff (equal text, named leaf differs) still fires and says DECLARATIONS DIFFER' (($m.THoldDiff -ne '') -and ($m.THoldDiff -cmatch 'DECLARATIONS DIFFER') -and ($m.THoldDiff -match 'TLeafDiff')) $m.THoldDiff
Check 'THoldSame (named leaf identical) fires and says identical, not NOT compared' (($m.THoldSame -match 'identical,') -and ($m.THoldSame -cnotmatch 'NOT compared') -and ($m.THoldSame -cnotmatch 'DIFFER')) $m.THoldSame
Check 'THoldGone (named type declared nowhere) stays NOT compared' (($m.THoldGone -cmatch 'NOT compared') -and ($m.THoldGone -notmatch 'identical,') -and ($m.THoldGone -cnotmatch 'DIFFER')) $m.THoldGone
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
