<#
  run_identifier_case_mismatch_refs.ps1 -- the store half of `identifier-case-mismatch` (1.42 lane
  ruleset): a ref the resolver bound to a project symbol, spelled in another case from its
  declaration. One finding per spelling per symbol per file. tests\lint\identifier-case-mismatch.pas
  holds the AST half; this one needs an index, which that harness does not have.

  RUN 1 lint-all --rule: exactly the TRIGGER lines. RUN 2 plain lint-all: the rule ships OFF.

  Usage: pwsh -File tests\lint-project\identifier-case-mismatch\run_identifier_case_mismatch_refs.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_icm_$PID"
$Rule    = 'identifier-case-mismatch'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}
function Parse-Findings([string[]]$Raw) {
  $txt = ($Raw -join "`n"); $b = $txt.IndexOf('[')
  $out = @(); if ($b -ge 0) { try { $out = @($txt.Substring($b) | ConvertFrom-Json) } catch { $out = @() } }
  if ($null -eq $out) { $out = @() }
  return ,@($out)
}
function LineOf([string]$File, [string]$Marker) {
  $m = @(Select-String -LiteralPath $File -SimpleMatch -Pattern "// $Marker")
  if ($m.Count -ne 1) { throw "marker '$Marker' found $($m.Count) times" }
  return [int]$m[0].LineNumber
}
try {
  $src = Join-Path $scratch 'src'
  [void](New-Item -ItemType Directory -Force -Path $src)
  Copy-Item (Join-Path $PSScriptRoot '*.pas') $src
  $db = Join-Path $scratch 'icm.sqlite'
  & $exePath index $src --db $db 2>&1 | Out-Null
  $use = Join-Path $src 'uIcmUse.pas'

  # positive-control: identifier-case-mismatch
  $hits = @((Parse-Findings (& $exePath lint-all --db $db --format json --rule $Rule 2>$null)) | Where-Object { $_.rule -eq $Rule })
  $lines = @($hits | ForEach-Object { [int]$_.start_line } | Sort-Object)
  $want  = @((LineOf $use 'TRIGGER-LOWER'), (LineOf $use 'TRIGGER-UPPER'), (LineOf $use 'TRIGGER-PROPERTY'), (LineOf $use 'TRIGGER-FUNCTION') | Sort-Object)
  Check 'RUN 1 exactly the TRIGGER lines fire' (($lines -join ',') -eq ($want -join ',')) "got [$($lines -join ',')] want [$($want -join ',')]"

  $off = @((Parse-Findings (& $exePath lint-all --db $db --format json 2>$null)) | Where-Object { $_.rule -eq $Rule })
  Check 'RUN 2 plain lint-all: the rule ships OFF' ($off.Count -eq 0) "$($off.Count) finding(s)"
} finally {
  if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }