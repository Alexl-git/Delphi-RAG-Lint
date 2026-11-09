<#
  run_convert_selection_editor_wiring.ps1 -- C12 ask N7 wiring guard (no IDE needed).

  The designer right-click entries (DragLint.Plugin.ConvertSelectionEditor) only exist in a
  live IDE, so their behaviour is an owner check. What CAN fail here, and is checked:
    1. the wizard's Register calls RegisterConvertSelectionEditor (else no entry at all);
    2. the package contains the unit;
    3. every designer verb caption is an ide-context surface of features\entries\
       convert-components.json (the registry names what the user sees).
  Positive control: the same check on a copy of Wizard.pas with the call removed MUST fail.

  RED, measured 2026-11-08 on base b036f2cb: check 1-3 FAIL (the unit did not exist).
  Usage: pwsh -File tests\plugin\run_convert_selection_editor_wiring.ps1
#>
[CmdletBinding()]
param([string]$Root = (Resolve-Path "$PSScriptRoot\..\..").Path)
$ErrorActionPreference = 'Stop'

function Get-RegisterBody([string]$Text) {
  $m = [regex]::Match($Text, '(?ms)^procedure Register;\s*\r?\nbegin(.*?)^end;')
  if ($m.Success) { return $m.Groups[1].Value } else { return '' }
}

function Test-Wiring([string]$WizardText, [string]$DpkText, [string]$UnitText, $Entry) {
  $fails = @()
  $body = Get-RegisterBody $WizardText
  if ($body -notmatch '\bRegisterConvertSelectionEditor\b') { $fails += 'Register does not call RegisterConvertSelectionEditor' }
  if ($DpkText -notmatch 'DragLint\.Plugin\.ConvertSelectionEditor in ') { $fails += 'dclDragLintWizard.dpk does not contain the unit' }
  $verbs = [regex]::Matches($UnitText, "CONVERT_VERB_\w+\s*=\s*'([^']+)'") | ForEach-Object { $_.Groups[1].Value }
  if (@($verbs).Count -lt 2) { $fails += "expected 2 verb captions in the unit, found $(@($verbs).Count)" }
  $captions = @($Entry.surfaces | Where-Object { $_.type -eq 'ide-context' } | ForEach-Object { $_.caption })
  foreach ($v in $verbs) { if ($captions -notcontains $v) { $fails += "verb '$v' is not an ide-context caption of convert-components" } }
  return ,$fails
}

$unitPath = Join-Path $Root 'src\delphi-plugin\DragLint.Plugin.ConvertSelectionEditor.pas'
$wizard = [IO.File]::ReadAllText((Join-Path $Root 'src\delphi-plugin\DragLint.Plugin.Wizard.pas'))
$dpk    = [IO.File]::ReadAllText((Join-Path $Root 'src\delphi-plugin\dclDragLintWizard.dpk'))
$unit   = if (Test-Path $unitPath) { [IO.File]::ReadAllText($unitPath) } else { '' }
$entry  = Get-Content (Join-Path $Root 'features\entries\convert-components.json') -Raw | ConvertFrom-Json

$bad = 0
$real = Test-Wiring $wizard $dpk $unit $entry
if ($real.Count -eq 0) { Write-Host 'PASS  wiring: Register call, package, registry captions' }
else { $bad++; Write-Host 'FAIL  wiring'; $real | ForEach-Object { Write-Host "      $_" } }

$mutated = [regex]::Replace($wizard, '(?m)^.*RegisterConvertSelectionEditor;.*\r?\n', '')
$ctrl = Test-Wiring $mutated $dpk $unit $entry
if ($ctrl -contains 'Register does not call RegisterConvertSelectionEditor') { Write-Host 'PASS  positive control: the guard fails with the Register call removed' }
else { $bad++; Write-Host 'FAIL  positive control: removing the Register call went unnoticed' }

if ($bad -gt 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0