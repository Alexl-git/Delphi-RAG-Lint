<#
  run_global_set_in_initialization_never_freed.ps1 -- the `global-set-in-initialization-never-freed`
  project rule (1.44 lane rulesf2).

  A unit's initialization sets its own global to a new object and nothing frees it. RUN 1: exactly the
  TRIGGER lines; every CONTROL line is silent (freed here, freed in another unit, an owner, an interface,
  a record, a factory, handed to a container). RUN 2: plain lint-all, the rule ships ON. RUN 3: a
  finalization frees GLeaked: its finding goes and the others stay, so the FREE decides.

  Usage: pwsh -File tests\lint-project\global-set-in-initialization-never-freed\run_global_set_in_initialization_never_freed.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_gf_$PID"
$Rule    = 'global-set-in-initialization-never-freed'
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
  $leak = Join-Path $src 'uGfLeak.pas'

  # positive-control: global-set-in-initialization-never-freed
  $hits  = RuleFindings $db @('--rule', $Rule)
  $lines = @($hits | ForEach-Object { [int]$_.start_line } | Sort-Object)
  $want  = @((LineOf $leak 'TRIGGER-PLAIN'), (LineOf $leak 'TRIGGER-ROUTINE'), (LineOf $leak 'TRIGGER-NILOWNER'), (LineOf $leak 'TRIGGER-LOCALCLASS') | Sort-Object)
  Check 'RUN 1 exactly the TRIGGER lines fire' (($lines -join ',') -eq ($want -join ',')) "got [$($lines -join ',')] want [$($want -join ',')]"
  Check 'RUN 1 the message names the variable and the class' (@($hits | Where-Object { $_.message -match 'GLeaked is set to a new TStringList' }).Count -eq 1) ''

  $off = RuleFindings $db @()
  Check 'RUN 2 plain lint-all: the rule ships ON' ($off.Count -eq $hits.Count -and $hits.Count -gt 0) "$($off.Count) finding(s)"

  $t = [IO.File]::ReadAllText($leak).Replace("  GFreed.Free;", "  GFreed.Free;`r`n  GLeaked.Free;")
  [IO.File]::WriteAllText($leak, $t, [Text.Encoding]::ASCII)
  & $exePath index $src --db $db 2>&1 | Out-Null
  $after = RuleFindings $db @('--rule', $Rule)
  Check 'RUN 3 freed in a finalization: GLeaked goes' (@($after | Where-Object { $_.message -match 'GLeaked' }).Count -eq 0) "$($after.Count) total"
  Check 'RUN 3 the other three stay' ($after.Count -eq 3) "$($after.Count) total"
} finally {
  if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }