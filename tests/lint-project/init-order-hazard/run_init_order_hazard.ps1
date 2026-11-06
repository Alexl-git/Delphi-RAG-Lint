<#
  run_init_order_hazard.ps1 -- the `init-order-hazard` project rule (1.44 lane rulesf2).

  An initialization section reaches a global of a unit that initializes later in the order computed
  from the .dpr, and that unit's initialization is what sets it. RUN 1: exactly the TRIGGER-* lines of
  uIohSecond. RUN 2: a plain lint-all, the rule ships OFF. RUN 3: the same units with the .dpr listing
  uIohSecond first: the order flips, so uIohSecond goes silent and uIohFirst's read of GSecond fires,
  so it is the COMPUTED ORDER that decides, not the shape of the code. RUN 4: no .dpr in the index: no
  order, no finding.

  Usage: pwsh -File tests\lint-project\init-order-hazard\run_init_order_hazard.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_ioh_$PID"
$Rule    = 'init-order-hazard'
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
  $second = Join-Path $src 'uIohSecond.pas'

  # positive-control: init-order-hazard
  $hits  = RuleFindings $db @('--rule', $Rule)
  $lines = @($hits | Where-Object { $_.file_path -like '*uIohSecond.pas' } | ForEach-Object { [int]$_.start_line } | Sort-Object)
  $want  = @((LineOf $second 'TRIGGER-CALL'), (LineOf $second 'TRIGGER-DIRECT'), (LineOf $second 'TRIGGER-NEW') | Sort-Object)
  Check 'RUN 1 exactly the TRIGGER lines fire in uIohSecond' (($lines -join ',') -eq ($want -join ',')) "got [$($lines -join ',')] want [$($want -join ',')]"
  Check 'RUN 1 uIohFirst reads uIohSecond safely (CONTROL-SAFE)' (@($hits | Where-Object { $_.file_path -like '*uIohFirst.pas' }).Count -eq 0) ''
  Check 'RUN 1 the message names the program and the variable' (@($hits | Where-Object { $_.message -match 'GFirst' -and $_.message -match 'fxIoh\.dpr' }).Count -eq 1) ''

  $off = RuleFindings $db @()
  Check 'RUN 2 plain lint-all: the rule ships OFF' ($off.Count -eq 0) "$($off.Count) finding(s)"

  $src3 = Fresh 'b'
  $dpr = Join-Path $src3 'fxIoh.dpr'
  $t = [IO.File]::ReadAllText($dpr)
  $t = $t.Replace("  uIohFirst in 'uIohFirst.pas',`r`n  uIohSecond in 'uIohSecond.pas',", "  uIohSecond in 'uIohSecond.pas',`r`n  uIohFirst in 'uIohFirst.pas',")
  [IO.File]::WriteAllText($dpr, $t, [Text.Encoding]::ASCII)
  $db3 = Join-Path $scratch 'b.sqlite'
  & $exePath index $src3 --db $db3 2>&1 | Out-Null
  $flip = RuleFindings $db3 @('--rule', $Rule)
  Check 'RUN 3 the other .dpr order: uIohSecond is silent' (@($flip | Where-Object { $_.file_path -like '*uIohSecond.pas' }).Count -eq 0) "$($flip.Count) total"
  Check 'RUN 3 the other .dpr order: uIohFirst now fires on GSecond' (@($flip | Where-Object { $_.file_path -like '*uIohFirst.pas' -and $_.message -match 'GSecond' }).Count -eq 1) ''

  $src4 = Fresh 'c'
  [IO.File]::Delete((Join-Path $src4 'fxIoh.dpr'))
  $db4 = Join-Path $scratch 'c.sqlite'
  & $exePath index $src4 --db $db4 2>&1 | Out-Null
  $none = RuleFindings $db4 @('--rule', $Rule)
  Check 'RUN 4 no .dpr: no order, no finding' ($none.Count -eq 0) "$($none.Count) finding(s)"
} finally {
  if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }