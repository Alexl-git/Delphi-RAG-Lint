#Requires -Version 7.3
<#
  run_docs_surface_harvest_lib.ps1 -- tests the STILL-LIVE shared harvest lib
  tests\autotest\lib\DocsSurfaceHarvest.ps1 (used by run_docs_sync_guard.ps1, checks 1 and 5):
  the help-verb parser, the caption normaliser (Get-CaptionKey folds '&&' and '...'),
  Test-CaptionKeyMatch, the live menu captions, and dialog buttons (TButton / TBitBtn /
  TSpeedButton) harvested APART from menu items (-ExcludeDialogButtons).

  Restored at fix round 1 of the featuregen cut-over: these checks lived in the retired
  run_feature_registry_harvest.ps1, whose other checks are now FeatureGenTests cases.
  (That runner also ran docs-sync as a child; docs-sync is its own battery member, so only
  the two source-level facts about it are kept here.)
#>
[CmdletBinding()]
param([string]$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
Write-Host '== docs surface harvest lib ==' -ForegroundColor Cyan

$lib = Join-Path $Repo 'tests\autotest\lib\DocsSurfaceHarvest.ps1'
Check 'harvest lib present' (Test-Path -LiteralPath $lib) $lib
if (-not (Test-Path -LiteralPath $lib)) { Write-Host 'DOCS SURFACE HARVEST LIB: FAIL' -ForegroundColor Red; exit 1 }
. $lib

# --- lib functions ----------------------------------------------------------
$planted = "Usage:`r`n  drag-lint query [--name X]`r`n  drag-lint zz-planted-verb --x`r`n     continuation line`r`n"
$pv = @(Get-HelpVerbList -HelpText $planted)
Check 'Get-HelpVerbList sees a planted verb line and not a continuation' (($pv -contains 'zz-planted-verb') -and ($pv -contains 'query') -and ($pv.Count -eq 2)) ($pv -join ' ')
# The normaliser also trims a trailing '(' / ')' (kept byte-identical), so
# 'Call Graph (Butterfly)...' keys to 'call graph (butterfly'.
Check 'Get-CaptionKey folds && and ...' ((Get-CaptionKey -S 'Uses && Dependencies') -eq 'uses & dependencies' -and (Get-CaptionKey -S 'Who calls this routine...') -eq 'who calls this routine' -and (Get-CaptionKey -S 'Call Graph (Butterfly)...') -eq 'call graph (butterfly')
Check 'Test-CaptionKeyMatch accepts a doc prefix of a live caption' (Test-CaptionKeyMatch -Key 'call graph' -LiveKeys @('call graph (butterfly)', 'about'))
Check 'Test-CaptionKeyMatch rejects an unrelated key' (-not (Test-CaptionKeyMatch -Key 'zz not a real menu item' -LiveKeys @('call graph (butterfly)', 'about')))
$caps = Get-LiveMenuCaptions -Repo $Repo
Check 'live captions harvested (>= 40)' ($caps.Count -ge 40) "($($caps.Count))"
Check 'a real caption is present' ($caps.Contains('About')) "'About'"
Check 'an invented caption is absent' (-not $caps.Contains('Zz Not A Real Menu Item'))
Check 'a Reports catalog caption is present' ($caps.Contains('Who calls this routine...'))

# --- dialog buttons are harvested APART from menu items ----------------------
# A '.Caption :=' on a variable declared or created as a TButton / TBitBtn /
# TSpeedButton is a dialog button, not a feature: it needs no exemption.
$dlg = @(Get-LiveDialogButtonCaptions -Repo $Repo)
$dlgWant = @('Go To', 'Fix', 'Cancel', 'Copy to clipboard')
Check 'dialog buttons harvested apart (Go To, Fix, Cancel, Copy to clipboard)' (@($dlgWant | Where-Object { $dlg -notcontains $_ }).Count -eq 0) ($dlg -join ' | ')
$mcx = Get-LiveMenuCaptions -Repo $Repo -ExcludeDialogButtons
Check 'and they are not main-menu captions (-ExcludeDialogButtons)' (@($dlgWant | Where-Object { $mcx.Contains($_) }).Count -eq 0)
Check 'menu items assigned with .Caption := still are (control)' ($mcx.Contains('Reports') -and $mcx.Contains('drag-lint (!)'))
$scr = Join-Path $env:TEMP "drag-lint-docs-surface-harvest-lib-$PID"
try {
  New-Item -ItemType Directory -Path (Join-Path $scr 'src\delphi-plugin') -Force | Out-Null
  $probe = "procedure P;`r`nvar`r`n  MiZz: TMenuItem;`r`n  BtnZz, BtnZz2: TButton;`r`nbegin`r`n  MiZz.Caption := 'Zz Menu Probe';`r`n  BtnZz.Caption := 'Zz Button Probe';`r`n  BtnZz2.Caption:= 'Zz Second Button';`r`n  var BitZz: TBitBtn:= TBitBtn.Create(nil);`r`n  BitZz.Caption := 'Zz Bit Probe';`r`n  FSpeedZz:= TSpeedButton.Create(nil);`r`n  FSpeedZz.Caption := 'Zz Speed Probe';`r`nend;`r`n"
  [IO.File]::WriteAllText((Join-Path $scr 'src\delphi-plugin\DragLint.Plugin.Editor.pas'), $probe, [Text.Encoding]::ASCII)
  $mc = Get-LiveMenuCaptions -Repo $scr -ExcludeDialogButtons
  $db = @(Get-LiveDialogButtonCaptions -Repo $scr)
  Check 'synthetic: a TMenuItem caption stays a menu caption (positive control)' ($mc.Contains('Zz Menu Probe')) ($mc -join ' | ')
  Check 'synthetic: TButton (multi-var decl), TBitBtn (inline var) and TSpeedButton (.Create) captions are dialog buttons' ((($db | Sort-Object) -join '|') -ceq 'Zz Bit Probe|Zz Button Probe|Zz Second Button|Zz Speed Probe') ($db -join ' | ')
  Check 'synthetic: and none of them is a menu caption' (@($db | Where-Object { $mc.Contains($_) }).Count -eq 0)
  Check 'without -ExcludeDialogButtons the docs-sync harvest is unchanged (buttons included)' ((Get-LiveMenuCaptions -Repo $scr).Contains('Zz Button Probe'))
} catch { Check 'dialog-button harvest functions exist and run' $false $_.Exception.Message }
finally { if (Test-Path -LiteralPath $scr) { [IO.Directory]::Delete($scr, $true) } }

# --- docs-sync really uses the shared lib ------------------------------------
$ds = Join-Path $Repo 'tests\autotest\run_docs_sync_guard.ps1'
$dsText = Get-Content -LiteralPath $ds -Raw
Check 'docs-sync no longer defines its own Get-CaptionKey' (-not ($dsText -match '(?m)^function Get-CaptionKey'))
Check 'docs-sync dot-sources the lib' ($dsText -match 'DocsSurfaceHarvest\.ps1')

# --- the two implementations agree (PowerShell lib vs featuregen's FeatureGen.Live port) ----------
# The harvest exists twice: this lib (docs-sync checks 1 and 5) and the Delphi port that
# featuregen's registry checks B / C use. This is the test that keeps them equal on the REAL repo.
Write-Host '-- PowerShell lib vs featuregen dump-live (real repo)' -ForegroundColor Cyan
function Compare-HarvestSets([string]$Kind, [string[]]$Ps, [string[]]$Port) {
  $onlyPs = @($Ps | Where-Object { $Port -cnotcontains $_ })
  $onlyPort = @($Port | Where-Object { $Ps -cnotcontains $_ })
  return [pscustomobject]@{ Kind = $Kind; OnlyPs = $onlyPs; OnlyPort = $onlyPort; Equal = (($onlyPs.Count + $onlyPort.Count) -eq 0) }
}
$cmpA = Compare-HarvestSets 'ctl' @('a', 'b') @('a', 'b')
$cmpB = Compare-HarvestSets 'ctl' @('a', 'b') @('a', 'c')
Check 'POSITIVE CONTROL: the set comparison is equal for equal sets and names a seeded difference' ($cmpA.Equal -and (-not $cmpB.Equal) -and ($cmpB.OnlyPs -contains 'b') -and ($cmpB.OnlyPort -contains 'c'))
. (Join-Path $Repo 'tools\featuregen-ensure.ps1')
$engine = Join-Path $Repo 'third_party\dll-win64\drag-lint.exe'
$fgExe = $null
try { $fgExe = Get-FeatureGenExe -Repo $Repo } catch { Check 'featuregen.exe is available and current' $false $_.Exception.Message }
if ($fgExe -and -not (Test-Path -LiteralPath $engine)) { Check 'engine available for the parity run' $false $engine; $fgExe = $null }
if ($fgExe) {
  $dump = @(& $fgExe dump-live --repo $Repo --engine $engine 2>&1)
  Check 'featuregen dump-live succeeds' ($LASTEXITCODE -eq 0) (($dump | Select-Object -First 3) -join ' / ')
  $portVerbs = @($dump | Where-Object { "$_" -like "verb`t*" } | ForEach-Object { ("$_" -split "`t", 2)[1] })
  $portCaps = @($dump | Where-Object { "$_" -like "caption`t*" } | ForEach-Object { ("$_" -split "`t", 2)[1] })
  $help = (& $engine --help 2>&1 | Out-String)
  $psVerbs = @(Get-HelpVerbList -HelpText $help)
  $psCaps = @((Get-LiveMenuCaptions -Repo $Repo -ExcludeDialogButtons))
  Check 'both harvests are non-trivial (verbs >= 20, captions >= 40)' (($psVerbs.Count -ge 20) -and ($portVerbs.Count -ge 20) -and ($psCaps.Count -ge 40) -and ($portCaps.Count -ge 40)) "(verbs ps=$($psVerbs.Count) port=$($portVerbs.Count); captions ps=$($psCaps.Count) port=$($portCaps.Count))"
  $cv = Compare-HarvestSets 'verbs' $psVerbs $portVerbs
  Check 'help verbs: PowerShell lib == featuregen port' $cv.Equal ("only-ps: $($cv.OnlyPs -join ', ') | only-port: $($cv.OnlyPort -join ', ')")
  $cc = Compare-HarvestSets 'captions' $psCaps $portCaps
  Check 'menu captions: PowerShell lib == featuregen port' $cc.Equal ("only-ps: $($cc.OnlyPs -join ' | ') | only-port: $($cc.OnlyPort -join ' | ')")
}

Write-Host ''
if ($script:Failed) { Write-Host 'DOCS SURFACE HARVEST LIB: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'DOCS SURFACE HARVEST LIB: PASS' -ForegroundColor Green
exit 0
