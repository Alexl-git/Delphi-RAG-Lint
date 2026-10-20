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

Write-Host ''
if ($script:Failed) { Write-Host 'DOCS SURFACE HARVEST LIB: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'DOCS SURFACE HARVEST LIB: PASS' -ForegroundColor Green
exit 0
