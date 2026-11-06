<#
  run_finalization_after_dependency.ps1 -- the `finalization-after-dependency` project rule (1.44 lane rulesf2).

  A finalization section reaches a global that a unit finalized earlier tears down. RUN 1: exactly the
  TRIGGER line of uFadSecond; the guarded read and the variable nobody tears down stay silent. RUN 2:
  plain lint-all, the rule ships OFF. RUN 3: the .dpr lists uFadSecond first, the order flips, so
  uFadFirst's read of GSecond fires and uFadSecond goes silent: the computed order decides.

  Usage: pwsh -File tests\lint-project\finalization-after-dependency\run_finalization_after_dependency.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_fad_$PID"
$Rule    = 'finalization-after-dependency'
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
function RuleFindings([string]$Db, [string[]]$Extra) {
  $raw = & $exePath lint-all --db $Db --format json @Extra 2>$null
  return @((Parse-Findings $raw) | Where-Object { $_.rule -eq $Rule })
}
function Fresh([string]$Name) {
  $d = Join-Path $scratch $Name
  [void](New-Item -ItemType Directory -Force -Path $d)
  Copy-Item (Join-Path $PSScriptRoot '*.pas') $d
  Copy-Item (Join-Path $PSScriptRoot '*.dpr') $d
  return $d
}
try {
  $src = Fresh 'a'
  $db = Join-Path $scratch 'a.sqlite'
  & $exePath index $src --db $db 2>&1 | Out-Null
  $second = Join-Path $src 'uFadSecond.pas'

  # positive-control: finalization-after-dependency
  $hits  = RuleFindings $db @('--rule', $Rule)
  $lines = @($hits | ForEach-Object { [int]$_.start_line } | Sort-Object)
  $want  = @(LineOf $second 'TRIGGER-CALL')
  Check 'RUN 1 exactly the TRIGGER line fires' (($lines -join ',') -eq ($want -join ',')) "got [$($lines -join ',')] want [$($want -join ',')]"
  Check 'RUN 1 it fires in uFadSecond, on GFirst' (@($hits | Where-Object { $_.file_path -like '*uFadSecond.pas' -and $_.message -match 'GFirst' -and $_.message -match 'fxFad\.dpr' }).Count -eq 1) ''

  $off = RuleFindings $db @()
  Check 'RUN 2 plain lint-all: the rule ships OFF' ($off.Count -eq 0) "$($off.Count) finding(s)"

  $src3 = Fresh 'b'
  $dpr = Join-Path $src3 'fxFad.dpr'
  $t = [IO.File]::ReadAllText($dpr)
  $t = $t.Replace("  uFadFirst in 'uFadFirst.pas',`r`n  uFadSecond in 'uFadSecond.pas';", "  uFadSecond in 'uFadSecond.pas',`r`n  uFadFirst in 'uFadFirst.pas';")
  [IO.File]::WriteAllText($dpr, $t, [Text.Encoding]::ASCII)
  $db3 = Join-Path $scratch 'b.sqlite'
  & $exePath index $src3 --db $db3 2>&1 | Out-Null
  $flip = RuleFindings $db3 @('--rule', $Rule)
  Check 'RUN 3 the other .dpr order: uFadSecond is silent' (@($flip | Where-Object { $_.file_path -like '*uFadSecond.pas' }).Count -eq 0) "$($flip.Count) total"
  Check 'RUN 3 the other .dpr order: uFadFirst now fires on GSecond' (@($flip | Where-Object { $_.file_path -like '*uFadFirst.pas' -and $_.message -match 'GSecond' }).Count -eq 1) ''
} finally {
  if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }