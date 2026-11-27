<#
  run_v156_FPS.ps1 -- 1.56 lane FP-S: two small false positives.
    1. pchar-arithmetic must not fire on PByte arithmetic (PByte has POINTERMATH ON; the byte-buffer idiom),
       while PChar / PAnsiChar / PWideChar / ^Char still fire (tests\lint\pchar-arithmetic.pas).
    2. concat-in-loop must be silent on a Variant / OleVariant target (the variant-in-loop rule reports it);
       tests\fixtures\v156\OOB2\VarFix.pas lines marked "FIRE variant-in-loop" give no concat-in-loop, and a
       target of unproven type still fires.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v156-fps-$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. (Join-Path $PSScriptRoot 'lib\EngineCompanions.ps1')
[void](Initialize-EngineCompanions -Exe $Exe)
$Exe = (Resolve-Path $Exe).Path
$Lint = (Resolve-Path "$PSScriptRoot\..\lint").Path
$Fix  = (Resolve-Path "$PSScriptRoot\..\fixtures\v156\OOB2").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$Src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $Src | Out-Null
Copy-Item "$Fix\VarFix.pas" $Src
Copy-Item "$Lint\pchar-arithmetic.pas" $Src
$Db  = Join-Path $WorkDir 'p.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $Src --db $Db 2>&1 | ForEach-Object { "$_" } } | Out-Null

function Get-Lines([string]$File, [string]$Rule) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe lint (Join-Path $Src $File) --db $Db --json 2>$null }
  $txt = ($raw | Where-Object { $_ -is [string] }) -join "`n"
  $i = $txt.IndexOf('['); if ($i -lt 0) { return @() }
  return ,@($txt.Substring($i) | ConvertFrom-Json | ForEach-Object { $_ } |
    Where-Object { $(if ($_.rule_id) { $_.rule_id } else { $_.rule }) -eq $Rule } | ForEach-Object { [int]$_.start_line })
}
function Marked([string]$File, [string]$Pat) {
  $n = 0
  return ,@(Get-Content (Join-Path $Src $File) | ForEach-Object { $n++; if ($_ -match $Pat) { $n } })
}

# positive-control: PChar lines still fire (12 13 39 40 42 44)
Write-Host 'pchar-arithmetic' -ForegroundColor Cyan
$pc = Get-Lines 'pchar-arithmetic.pas' 'pchar-arithmetic'
$byteLines = 36, 51, 52, 53, 54
Check 'no finding on a PByte line' (@($pc | Where-Object { $byteLines -contains $_ }).Count -eq 0) ($pc -join ',')
Check 'PChar / PAnsiChar / PWideChar / ^Char lines still fire' ((($pc | Sort-Object) -join ',') -eq '12,13,39,40,42,44') ($pc -join ',')

# positive-control: concat-in-loop on a target of unproven type (line "UnknownThing") still fires
Write-Host 'concat-in-loop on Variant' -ForegroundColor Cyan
$cl = Get-Lines 'VarFix.pas' 'concat-in-loop'
$var = Marked 'VarFix.pas' '// FIRE variant-in-loop'
Check 'fixture has 4 variant-in-loop lines' ($var.Count -eq 4) ($var -join ',')
Check 'no concat-in-loop on a variant-in-loop line' (@($cl | Where-Object { $var -contains $_ }).Count -eq 0) ($cl -join ',')
$unk = Marked 'VarFix.pas' 'UnknownThing:= UnknownThing'
Check 'concat-in-loop still fires on the unproven target' (@($cl | Where-Object { $unk -contains $_ }).Count -eq 1) ($cl -join ',')
} finally {
  if ($WorkDir -and (Test-Path $WorkDir)) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASSED' -ForegroundColor Green
