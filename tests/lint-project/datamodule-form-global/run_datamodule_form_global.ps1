<#
  run_datamodule_form_global.ps1 -- the `datamodule-form-global` project rule (1.42 lane ruleset).

  A unit that declares a TDataModule descendant reads or writes another unit's global form
  variable. RUN 1 asks for the rule: exactly the TRIGGER-* lines, one finding per (unit, variable),
  anchored at the first reference. RUN 2 is a plain lint-all: the rule ships OFF, so nothing.
  RUN 3 is a scratch copy where the class stops descending from TDataModule: the same reads are now
  silent, so the triggers fire because of the module and not by accident. RUN 4 adds a one-unit
  library index: TViaLibForm's base class is only there, so TRIGGER-LIB fires ONLY with it (a form on
  TdxRibbonForm, the Loader2025 shape).

  Usage: pwsh -File tests\lint-project\datamodule-form-global\run_datamodule_form_global.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_dmfg_$PID"
$Rule    = 'datamodule-form-global'
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
try {
  $src = Join-Path $scratch 'src'
  [void](New-Item -ItemType Directory -Force -Path $src)
  Copy-Item (Join-Path $PSScriptRoot '*.pas') $src
  $db = Join-Path $scratch 'dmfg.sqlite'
  & $exePath index $src --db $db 2>&1 | Out-Null
  $mod = Join-Path $src 'uDmfModule.pas'

  # positive-control: datamodule-form-global
  $hits = RuleFindings $db @('--rule', $Rule)
  $inModule = @($hits | Where-Object { $_.file_path -like '*uDmfModule.pas' })
  $lines = @($inModule | ForEach-Object { [int]$_.start_line } | Sort-Object)
  $want  = @((LineOf $mod 'TRIGGER-MAIN'), (LineOf $mod 'TRIGGER-PLAIN') | Sort-Object)
  Check 'RUN 1 exactly the TRIGGER lines fire in the data module' (($lines -join ',') -eq ($want -join ',')) "got [$($lines -join ',')] want [$($want -join ',')]"
  Check 'RUN 1 nothing fires outside the data module (CONTROL-NOTMODULE)' ($hits.Count -eq $inModule.Count) "$($hits.Count) total"
  Check 'RUN 1 the message counts both references of MainForm' (@($inModule | Where-Object { $_.message -match 'MainForm' -and $_.message -match '\b2 time' }).Count -eq 1) ''

  $off = RuleFindings $db @()
  Check 'RUN 2 plain lint-all: the rule ships OFF' ($off.Count -eq 0) "$($off.Count) finding(s)"

  $libSrc = Join-Path $scratch 'libsrc'
  [void](New-Item -ItemType Directory -Force -Path $libSrc)
  Copy-Item (Join-Path $PSScriptRoot 'lib\*.pas') $libSrc
  $libDb = Join-Path $scratch 'library-dmfg.sqlite'
  & $exePath index $libSrc --db $libDb 2>&1 | Out-Null
  $withLib = @((Parse-Findings (& $exePath lint-all --db $db --db $libDb --format json --rule $Rule 2>$null)) | Where-Object { $_.rule -eq $Rule } | ForEach-Object { [int]$_.start_line })
  $libLine = LineOf $mod 'TRIGGER-LIB'
  Check 'RUN 4 with the library: the form on a library base class fires' ($withLib -contains $libLine) "got [$($withLib -join ',')] want $libLine"
  Check 'RUN 1 without the library: that form is unknown and silent' ($lines -notcontains $libLine) ''

  $t = [IO.File]::ReadAllText($mod).Replace('class(TDataModule)', 'class(TObject)')
  [IO.File]::WriteAllText($mod, $t, [Text.Encoding]::ASCII)
  & $exePath index $src --db $db 2>&1 | Out-Null
  $gone = RuleFindings $db @('--rule', $Rule)
  Check 'RUN 3 no TDataModule in the unit: the same reads are silent' ($gone.Count -eq 0) "$($gone.Count) finding(s)"
} finally {
  if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }