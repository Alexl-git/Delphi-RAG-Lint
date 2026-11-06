<#
  run_heavy_initialization.ps1 -- the `heavy-initialization` project rule (1.44 lane rulesf2).

  An initialization section reaches a file, the registry, the network, a database or a dialog. RUN 1:
  exactly the TRIGGER lines, one per section; a routine nobody calls, TPath string work and a
  finalization stay silent. RUN 2: plain lint-all, the rule ships OFF. RUN 3: the section of uHiChain
  stops calling Boot, so the same routine is unreachable and the finding goes: the WALK fires it, not
  the name in the file.

  Usage: pwsh -File tests\lint-project\heavy-initialization\run_heavy_initialization.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_hi_$PID"
$Rule    = 'heavy-initialization'
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
  return $d
}
try {
  $src = Fresh 'a'
  $db = Join-Path $scratch 'a.sqlite'
  & $exePath index $src --db $db 2>&1 | Out-Null

  # positive-control: heavy-initialization
  $hits  = RuleFindings $db @('--rule', $Rule)
  $direct = LineOf (Join-Path $src 'uHiFile.pas') 'TRIGGER-DIRECT'
  $chain  = LineOf (Join-Path $src 'uHiChain.pas') 'TRIGGER-CHAIN'
  Check 'RUN 1 two findings, one per heavy section' ($hits.Count -eq 2) "$($hits.Count) finding(s)"
  Check 'RUN 1 the direct read fires at its line, as file system' (@($hits | Where-Object { $_.file_path -like '*uHiFile.pas' -and [int]$_.start_line -eq $direct -and $_.message -match 'file system' }).Count -eq 1) ''
  Check 'RUN 1 the chain fires at the section call, as registry, naming the routine' (@($hits | Where-Object { $_.file_path -like '*uHiChain.pas' -and [int]$_.start_line -eq $chain -and $_.message -match 'registry \(uHiChain\.LoadFromRegistry\)' }).Count -eq 1) ''
  Check 'RUN 1 nothing fires in uHiLight' (@($hits | Where-Object { $_.file_path -like '*uHiLight.pas' }).Count -eq 0) ''

  $off = RuleFindings $db @()
  Check 'RUN 2 plain lint-all: the rule ships OFF' ($off.Count -eq 0) "$($off.Count) finding(s)"

  $f = Join-Path $src 'uHiChain.pas'
  $t = [IO.File]::ReadAllText($f).Replace("  Boot; // TRIGGER-CHAIN", "  // no call")
  [IO.File]::WriteAllText($f, $t, [Text.Encoding]::ASCII)
  & $exePath index $src --db $db 2>&1 | Out-Null
  $gone = RuleFindings $db @('--rule', $Rule)
  Check 'RUN 3 the section stops calling: the chain finding goes' (@($gone | Where-Object { $_.file_path -like '*uHiChain.pas' }).Count -eq 0) "$($gone.Count) total"
} finally {
  if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }