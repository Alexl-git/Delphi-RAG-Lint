<#
  run_v151_LIBFX_lib_effects.ps1 -- E-BIND-LIB-EFFECTS: the purity stage takes a
  library routine's stored effect summary for a call whose resolved
  external_target names it. ON by default: the library comes from the DB's own
  external_stores meta (what --library-db bound the edges against);
  DRAGLINT_LIBRARY_EFFECTS=0 turns it off for one run.

  Fixture: tests\autotest\fixtures\v151-LIBFX\lib-effects\
    lib\LibFxLib.pas   indexed as a folder into lib.sqlite
    proj\LibFxUse.pas  indexed with --library-db lib.sqlite, once with
                       DRAGLINT_LIBRARY_EFFECTS=0 (OFF) and once with
                       it unset (ON, the default)

    c1  OFF: Wrap stays the bare unbound `?` and side-effect-in-short-circuit
        is silent (positive control: the switch, not the fixture, makes c2)
    c2  ON : Wrap carries g (from BumpCounter) and the rule fires once, on the
        `AFlag and Wrap()` line of CheckBoth
    c3  ON : every library summary keeps `?` -- SumWrap (calls the effect-free
        PlainSum) is NOT proven effect-free, and CheckPure stays silent
    c4  ON : a virtual library member stays `?` -- VirtWrap does not take g
        from TLibFxObj.VirtBump, and CheckVirt stays silent
    c5  ON : h is not taken from the library -- FreeWrap does not take h
        from FreeTemp
    c6  ON : the stage reports how many call refs took a library summary

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\draglint_v151_libfx_$PID",
  [switch]$Quiet
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([bool]$ok, [string]$what) {
  if ($ok) { if (-not $Quiet) { Write-Host "PASS  $what" } }
  else     { Write-Host "FAIL  $what" -ForegroundColor Red; $script:fail = $true }
}
function Parse-Findings([string[]]$Raw) {
  $txt = ($Raw -join "`n"); $b = $txt.IndexOf('[')
  $out = @(); if ($b -ge 0) { try { $out = @(($txt.Substring($b) | ConvertFrom-Json) | ForEach-Object { $_ }) } catch { $out = @() } }
  return ,@($out)
}
# sql --json rows are POSITIONAL arrays: map rows[i][k] onto columns[k].name.
function Get-Summaries([string]$Db) {
  $q = 'select s.qualified_name, f.effect_summary from symbols s join symbol_facts f on f.symbol_id = s.id'
  $j = (& { $ErrorActionPreference = 'Continue'; & $exePath sql --query $q --db $Db --json 2>$null }) -join "`n" | ConvertFrom-Json
  $map = @{}
  foreach ($r in $j.rows) { $map[[string]$r[0]] = [string]$r[1] }
  return $map
}
function Has-Flag([string]$Summary, [string]$Flag) {
  return @($Summary -split ',' | Where-Object { $_ -eq $Flag }).Count -gt 0
}

$exePath = (Resolve-Path $Exe).Path
$rule    = 'side-effect-in-short-circuit'
$src     = Join-Path $PSScriptRoot 'fixtures\v151-LIBFX\lib-effects'
New-Item -ItemType Directory -Force $WorkDir | Out-Null
Copy-Item (Join-Path $src 'lib')  $WorkDir -Recurse -Force
Copy-Item (Join-Path $src 'proj') $WorkDir -Recurse -Force
$lib   = Join-Path $WorkDir 'lib.sqlite'
$dbOff = Join-Path $WorkDir 'off.sqlite'
$dbOn  = Join-Path $WorkDir 'on.sqlite'
$use   = Join-Path $WorkDir 'proj\LibFxUse.pas'
$line  = (Select-String -LiteralPath $use -Pattern 'AFlag and Wrap\(\)' | Select-Object -First 1).LineNumber

$savedSwitch = $env:DRAGLINT_LIBRARY_EFFECTS
Push-Location $env:TEMP
try {
  & { $ErrorActionPreference = 'Continue'; & $exePath index (Join-Path $WorkDir 'lib') --db $lib *> $null }

  $env:DRAGLINT_LIBRARY_EFFECTS = '0'
  & { $ErrorActionPreference = 'Continue'; & $exePath index (Join-Path $WorkDir 'proj') --db $dbOff --library-db $lib *> $null }
  $env:DRAGLINT_LIBRARY_EFFECTS = $null
  $logOn = (& { $ErrorActionPreference = 'Continue'; & $exePath index (Join-Path $WorkDir 'proj') --db $dbOn --library-db $lib 2>&1 | ForEach-Object { "$_" } }) -join "`n"
  $env:DRAGLINT_LIBRARY_EFFECTS = $null

  $off = Get-Summaries $dbOff
  $on  = Get-Summaries $dbOn
  $fOff = @(Parse-Findings (& { $ErrorActionPreference = 'Continue'; & $exePath lint-all --db $dbOff --library-db $lib --rule $rule --json 2>$null }) | Where-Object { $_.rule -eq $rule })
  $fOn  = @(Parse-Findings (& { $ErrorActionPreference = 'Continue'; & $exePath lint-all --db $dbOn  --library-db $lib --rule $rule --json 2>$null }) | Where-Object { $_.rule -eq $rule })

  Check (($off['LibFxUse.Wrap'] -eq '?') -and ($fOff.Count -eq 0)) "c1 OFF: Wrap is '?' (got '$($off['LibFxUse.Wrap'])') and $rule is silent (got $($fOff.Count))"
  Check ((Has-Flag $on['LibFxUse.Wrap'] 'g') -and ($fOn.Count -eq 1) -and ($fOn[0].start_line -eq $line)) "c2 ON: Wrap carries g (got '$($on['LibFxUse.Wrap'])'), $rule fires once at line $line (got $($fOn.Count): $(($fOn | ForEach-Object start_line) -join ','))"
  Check ((Has-Flag $on['LibFxUse.SumWrap'] '?') -and -not (@($fOn | Where-Object { $_.message -like '*SumWrap*' }).Count)) "c3 ON: SumWrap keeps '?' (got '$($on['LibFxUse.SumWrap'])'), CheckPure silent"
  Check ((-not (Has-Flag $on['LibFxUse.VirtWrap'] 'g')) -and (Has-Flag $on['LibFxUse.VirtWrap'] '?')) "c4 ON: VirtWrap stays '?' without g (got '$($on['LibFxUse.VirtWrap'])')"
  Check ((-not (Has-Flag $on['LibFxUse.FreeWrap'] 'h')) -and (Has-Flag $on['LibFxUse.FreeWrap'] '?')) "c5 ON: FreeWrap takes no h (got '$($on['LibFxUse.FreeWrap'])')"
  Check ($logOn -match 'purity library effects -- [1-9]\d* call ref\(s\) took a library summary') "c6 ON: the stage reports the library call refs it took"
} finally {
  $env:DRAGLINT_LIBRARY_EFFECTS = $savedSwitch
  Pop-Location
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:fail) { Write-Host 'run_v151_LIBFX_lib_effects: FAIL'; exit 1 }
Write-Host 'run_v151_LIBFX_lib_effects: PASS'
exit 0
