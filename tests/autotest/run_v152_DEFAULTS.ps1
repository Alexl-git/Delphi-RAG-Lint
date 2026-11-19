<#
  run_v152_DEFAULTS.ps1 -- lane DEFAULTS (1.52): default flips + the form-object-without-field exempt-class list (PLAN D3).
  1. rules --json: dataset-edit-without-post, foreign-form-control-access, form-object-without-field are default_enabled.
     datamodule-form-global: its flip lives in RuleCatalog / ProjectRules / CLI (not this lane's files); reported as
     HANDOVER-PENDING and a failure only with -Strict (INT passes -Strict after applying the handover).
  2. Exempt list, in a SANDBOX copy of the exe (so the shipped list can be edited): a class on the shipped list is silent;
     removed from the list it fires; "use_default_list": false -> fires; project "exempt_classes" silences; trailing * wildcard.
  Fixture: fixtures\v1511-V151F\t03 (Label1: TLabel, dxBarButton2: TdxBarButton whose name the unit uses by string).
  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$Strict)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n)
  if (-not $ok) { if ($d) { Write-Host "      $d" }; $script:fail = $true }
}
$srcExe = (Resolve-Path $Exe).Path
$srcDir = Split-Path $srcExe
# sandbox: exe + companions + rules, so the shipped list can be edited without touching the engine under test
$box = Join-Path ([IO.Path]::GetTempPath()) ("v152def-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
[void][IO.Directory]::CreateDirectory($box)
Get-ChildItem $srcDir -File | Where-Object { $_.Extension -in '.exe', '.dll', '.json', '.castlib' } | Copy-Item -Destination $box
[void][IO.Directory]::CreateDirectory("$box\rules")
Copy-Item "$srcDir\rules\*" "$box\rules" -Recurse -ErrorAction SilentlyContinue
$exe = Join-Path $box 'drag-lint.exe'
$listFile = "$box\rules\form-object-without-field.exempt.txt"
$fx = Join-Path $PSScriptRoot 'fixtures\v1511-V151F\t03'
$pas = Join-Path $fx 'UBars.pas'; $dfm = Join-Path $fx 'UBars.dfm'
$r = 'form-object-without-field'

# 1. defaults
$rules = (& { $ErrorActionPreference = 'Continue'; & $exe rules --json 2>$null }) -join "`n" | ConvertFrom-Json
$rl = if ($rules -is [array]) { $rules } else { $rules.rules }
foreach ($id in 'dataset-edit-without-post', 'foreign-form-control-access', 'form-object-without-field') {
  $x = $rl | Where-Object { $_.id -eq $id }
  Check "default ON: $id" ($null -ne $x -and $x.default_enabled -eq $true) "default_enabled=$($x.default_enabled)"
}
$dm = $rl | Where-Object { $_.id -eq 'datamodule-form-global' }
if ($Strict) { Check 'default ON: datamodule-form-global' ($dm.default_enabled -eq $true) }
else { Write-Host ("[{0}] datamodule-form-global default_enabled={1} (handover to INT: RuleCatalog / ProjectRules / CLI)" -f $(if ($dm.default_enabled) { 'PASS' } else { 'HANDOVER-PENDING' }), $dm.default_enabled) }

# 2. exempt list. NO --enable: the rule must now be on by default.
function Lines([string]$cfg) {
  $a = @('lint', $pas, '--json', '--rule', $r)
  if ($cfg) { $a += @('--config', $cfg) }
  $raw = (& { $ErrorActionPreference = 'Continue'; & $exe @a 2>$null }) -join "`n"
  if ($raw.Trim() -eq '') { return @() }
  @($raw | ConvertFrom-Json | Where-Object { $_.rule -eq $r } | ForEach-Object { "$($_.start_line)" })
}
function LineOf($pat) { $l = [IO.File]::ReadAllLines($dfm); for ($i = 0; $i -lt $l.Count; $i++) { if ($l[$i] -match $pat) { return $i + 1 } }; -1 }
function Cfg($json) { $p = Join-Path $box ("c" + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.json'); [IO.File]::WriteAllText($p, $json); $p }
$lLabel = "$(LineOf 'object Label1\b')"; $lBtn = "$(LineOf 'object dxBarButton2\b')"
$noList = Cfg '{"form_object_without_field": {"use_default_list": false}}'

[IO.File]::WriteAllText($listFile, "# test list`r`nTLabel`r`n")
$g = @(Lines $null)
Check 'list has TLabel: Label1 silent' (-not ($g -contains $lLabel)) ($g -join ' ')
Check 'list has TLabel: dxBarButton2 (not listed) still fires (positive control)' ($g -contains $lBtn) ($g -join ' ')
$g = @(Lines $noList)
Check 'use_default_list false: Label1 fires' ($g -contains $lLabel) ($g -join ' ')
[IO.File]::WriteAllText($listFile, "# test list`r`n")
$g = @(Lines $null)
Check 'TLabel removed from list: Label1 fires' ($g -contains $lLabel) ($g -join ' ')
[IO.File]::WriteAllText($listFile, "TdxBarB*`r`n")
$g = @(Lines $null)
Check 'wildcard TdxBarB*: dxBarButton2 silent' (-not ($g -contains $lBtn)) ($g -join ' ')
Check 'wildcard TdxBarB*: Label1 fires' ($g -contains $lLabel) ($g -join ' ')
[IO.File]::WriteAllText($listFile, "")
$g = @(Lines (Cfg '{"form_object_without_field": {"exempt_classes": ["tlabel"]}}'))
Check 'project exempt_classes tlabel (case-insensitive): Label1 silent' (-not ($g -contains $lLabel)) ($g -join ' ')
Check 'project exempt_classes: dxBarButton2 fires' ($g -contains $lBtn) ($g -join ' ')

if ($script:fail) { Write-Host 'RESULT: FAIL'; exit 1 } else { Write-Host 'RESULT: PASS' }
