<#
  run_v151_INC_seal_forward.ps1 -- a type named through its FORWARD declaration (`TFoo = class;`,
  completed later as `TFoo = class sealed`) binds to the completing declaration, so is-never-true
  sees `sealed` (v151 lane INC, finishing EXT's PARTIAL RP-SEALED-forward).

  Fixtures:
    tests\autotest\fixtures\v151-EXT\uSealShapes.pas  line 45 `F is TShFwd` (EXT's shape).
    tests\autotest\fixtures\v151-INC\uSealFwd.pas     line 30 `I is TFwdSealed` (bare), line 31
      `I is uSealFwd.TFwdSealed` (unit-qualified); control line 32 `I is TFwdOpen` (forward of a
      class that is NOT sealed: must not fire).

  Positive control: with the rule disabled the must-fire lines are gone (the count cannot come from
  a rule that always fires).

  Usage: pwsh -File tests\autotest\run_v151_INC_seal_forward.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
. "$repo\tests\autotest\lib\HermeticEngine.ps1"; $exePath = Get-HermeticEngine $exePath
$scratch = Join-Path ([IO.Path]::GetTempPath()) "draglint_sealfwd_$PID"
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  Write-Host ("[{0}] {1}{2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}
function Lines([string]$File, [string]$Db, [string[]]$Extra) {
  $sel = @(if ($Extra.Count -gt 0) { $Extra } else { @('--rule', 'is-never-true') })
  $raw = (& { $ErrorActionPreference = 'Continue'; & $exePath lint $File --db $Db --json @sel 2>$null }) -join "`n"
  $j = @(($raw | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ })
  return ,@($j | Where-Object { $_.rule -eq 'is-never-true' } | ForEach-Object { [int]$_.start_line })
}
try {
  [void](New-Item -ItemType Directory -Force -Path $scratch)
  $fx = Join-Path $scratch 'fx'
  [void](New-Item -ItemType Directory -Force -Path $fx)
  Copy-Item (Join-Path $PSScriptRoot 'fixtures\v151-EXT\uSealShapes.pas') $fx
  Copy-Item (Join-Path $PSScriptRoot 'fixtures\v151-INC\uSealFwd.pas') $fx
  $db = Join-Path $scratch 'seal.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $exePath index $fx --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
  $a = Lines (Join-Path $fx 'uSealShapes.pas') $db @()
  Check 'uSealShapes: line 45 (F is TShFwd, forward of a sealed class) fires' ($a -contains 45) ($a -join ',')
  Check 'uSealShapes: lines 41-44 still fire' ((@(41, 42, 43, 44) | Where-Object { $a -notcontains $_ }).Count -eq 0) ($a -join ',')
  $b = Lines (Join-Path $fx 'uSealFwd.pas') $db @()
  Check 'uSealFwd: line 30 (bare forward name) fires' ($b -contains 30) ($b -join ',')
  Check 'uSealFwd: line 31 (unit-qualified forward name) fires' ($b -contains 31) ($b -join ',')
  Check 'control: line 32 (forward of a class that is not sealed) does not fire' ($b -notcontains 32) ($b -join ',')
  $c = Lines (Join-Path $fx 'uSealFwd.pas') $db @('--disable', 'is-never-true')
  Check 'positive control: rule disabled -> no finding' ($c.Count -eq 0) ($c -join ',')
} finally {
  if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
Write-Host ''
if ($script:fail) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0
