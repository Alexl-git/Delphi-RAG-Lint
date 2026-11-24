<#
  run_v154_DFM.ps1 -- 1.54 lane DFM: dfm-duplicate-tab-order, dfm-conflicting-accelerator, dfm-conflicting-shortcut,
  dfm-action-and-onclick, db-component-on-form, dfm-default-component-name, dfm-hint-inactive and the shipped default
  policy of disallowed-dfm-property, on tests\fixtures\v154\DFM (form + unit pairs).
  Every rule is compared as an EXACT set of "<form file>:<line>": each fixture holds firing controls (listed below) and
  silent controls (the neighbours of the same file), so a rule that fires too much or too little fails.
  Also: the defaults (four ON, three OFF) and the project policy that takes over a default.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v154-dfm-$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fix = (Resolve-Path "$PSScriptRoot\..\fixtures\v154\DFM").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$Src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $Src | Out-Null
Copy-Item "$Fix\*" $Src
$OnCfg = Join-Path $WorkDir 'on.json'
$PolCfg = Join-Path $WorkDir 'policy.json'
$OffCfg = Join-Path $WorkDir 'off.json'
[IO.File]::WriteAllText($OnCfg, '{"enabled":["db-component-on-form","dfm-default-component-name","dfm-hint-inactive"]}', [Text.Encoding]::ASCII)
[IO.File]::WriteAllText($PolCfg, '{"disallowed":{"names":[{"name":"dfm:TFDConnection.Connected=True","reason":"project"}]}}', [Text.Encoding]::ASCII)
[IO.File]::WriteAllText($OffCfg, '{}', [Text.Encoding]::ASCII)

# "form:line" set (sorted) of the findings of one rule over every fixture unit; $Rule '' = every rule, "form:line rule"
function Get-Found([string]$Rule, [string]$Cfg) {
  $out = @()
  foreach ($f in (Get-ChildItem $Src -Filter *.pas | Sort-Object Name)) {
    $argv = @('lint', $f.FullName, '--config', $Cfg, '--json')
    if ($Rule) { $argv += @('--rule', $Rule) }
    $raw = & { $ErrorActionPreference = 'Continue'; & $Exe @argv 2>$null }
    $txt = ($raw | Where-Object { $_ -is [string] }) -join "`n"
    $i = $txt.IndexOf('['); if ($i -lt 0) { continue }
    foreach ($x in @($txt.Substring($i) | ConvertFrom-Json | ForEach-Object { $_ })) {
      $r = if ($x.rule_id) { $x.rule_id } else { $x.rule }
      if ($Rule -and $r -ne $Rule) { continue }
      $p = if ($x.file_path) { $x.file_path } elseif ($x.path) { $x.path } else { $x.file }
      $out += ("{0}:{1} {2}" -f (Split-Path $p -Leaf), $x.start_line, $r)
    }
  }
  return ,@($out | Sort-Object -Unique)
}
function Compare-Rule([string]$Rule, [string]$Cfg, [string[]]$Want) {
  $got = Get-Found $Rule $Cfg
  $w = @($Want | ForEach-Object { "$_ $Rule" } | Sort-Object)
  Check "$Rule has firing controls" ($w.Count -gt 0)
  $missed = @($w | Where-Object { $got -notcontains $_ })
  $extra  = @($got | Where-Object { $w -notcontains $_ })
  Check "$Rule fires exactly on its controls" (($missed.Count -eq 0) -and ($extra.Count -eq 0)) ("missed: $($missed -join ', ') extra: $($extra -join ', ')")
}

Write-Host 'THE RULES' -ForegroundColor Cyan
# positive-control: dfm-duplicate-tab-order
Compare-Rule 'dfm-duplicate-tab-order' $OnCfg @('TabForm.dfm:11')
# positive-control: dfm-conflicting-accelerator
Compare-Rule 'dfm-conflicting-accelerator' $OnCfg @('AccelForm.dfm:9', 'AccelForm.dfm:17', 'AccelForm.dfm:56')
# positive-control: dfm-conflicting-shortcut
Compare-Rule 'dfm-conflicting-shortcut' $OnCfg @('ShortcutForm.dfm:10', 'ShortcutForm.dfm:43', 'ShortcutForm.dfm:55')
# positive-control: dfm-action-and-onclick
Compare-Rule 'dfm-action-and-onclick' $OnCfg @('ActionForm.dfm:12', 'ActionForm.dfm:27')
# positive-control: db-component-on-form
Compare-Rule 'db-component-on-form' $OnCfg @('DbForm.dfm:3', 'DbForm.dfm:6', 'PolicyForm.dfm:3', 'PolicyForm.dfm:6', 'PolicyForm.dfm:9', 'PolicyForm.dfm:13')
# positive-control: dfm-default-component-name
Compare-Rule 'dfm-default-component-name' $OnCfg @('NameForm.dfm:3', 'NameForm.dfm:12', 'NameForm.dfm:18', 'HintCode.dfm:3')
# positive-control: dfm-hint-inactive
Compare-Rule 'dfm-hint-inactive' $OnCfg @('HintForm.dfm:4', 'HintForm.dfm:23')
# positive-control: disallowed-dfm-property (shipped default)
Compare-Rule 'disallowed-dfm-property' $OffCfg @('PolicyForm.dfm:4', 'PolicyForm.dfm:10')

Write-Host 'THE PROJECT POLICY TAKES OVER A DEFAULT' -ForegroundColor Cyan
$pol = Get-Found 'disallowed-dfm-property' $PolCfg
# the project names Connected: the connection is judged by ITS entry (still reported, with the reason), Active keeps the default
$polText = (& { $ErrorActionPreference = 'Continue'; & $Exe lint (Join-Path $Src 'PolicyForm.pas') --config $PolCfg --rule disallowed-dfm-property --json 2>$null }) -join "`n"
Check 'Connected: one finding, the project entry (reason named), not the default' (($polText -match 'by project policy -- project') -and (([regex]::Matches($polText, 'default policy')).Count -eq 1)) $polText
Check 'Active: the default still fires' (@($pol | Where-Object { $_ -like 'PolicyForm.dfm:10 *' }).Count -eq 1) ($pol -join ', ')
Check 'no line is reported twice' (@($pol).Count -eq 2) ($pol -join ', ')

Write-Host 'DEFAULTS' -ForegroundColor Cyan
$all = Get-Found '' $OffCfg
$ids = @($all | ForEach-Object { ($_ -split ' ')[1] } | Sort-Object -Unique)
foreach ($on in 'dfm-duplicate-tab-order', 'dfm-conflicting-accelerator', 'dfm-conflicting-shortcut', 'dfm-action-and-onclick', 'disallowed-dfm-property') {
  Check "$on is ON by default" ($ids -contains $on) ($ids -join ', ')
}
foreach ($off in 'db-component-on-form', 'dfm-default-component-name', 'dfm-hint-inactive') {
  Check "$off is OFF by default" ($ids -notcontains $off) ($ids -join ', ')
}

if ($script:Failed) { Write-Host "FAIL ($script:Passed passed)" -ForegroundColor Red; exit 1 }
Write-Host "PASS ($script:Passed checks)" -ForegroundColor Green
exit 0
} finally {
  if (($WorkDir -like "$env:TEMP\drag-lint-v154-dfm-$PID*") -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
