<#
  run_unused_global.ps1 -- the `unused-global` project lint rule (1.40 lane unusedg).

  A unit-level const / var / type that no ref names: implementation-section ones
  per declaring file (exact), interface-section const / var / type alias per
  project (any file). Interface classes are public API and never reported.

    RUN 1  lint-all (ON by default)  -> exactly the TRIGGER-* lines; every CONTROL-* silent
    RUN 2  --rule / --disable        -> the same 7 / none
    RUN 3  scratch copy with the only uses removed (nested routine, initialization,
           typed-const initializer, other unit) -> those four CONTROL symbols fire
           (positive control: the single use drives the silence)

  Line numbers come from the fixture's TRIGGER-* / CONTROL-* markers.
  `lint --json` is a BARE ARRAY whose line key is `start_line`.

  Usage: pwsh -File tests\lint-project\unused-global\run_unused_global.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$fixture = Join-Path $PSScriptRoot 'uUnusedGlobal.pas'
$scratch = Join-Path C:\TEMP "draglint_unused_global_$PID"
$Rule    = 'unused-global'
try {
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path (Join-Path $scratch 'src') | Out-Null
Copy-Item (Join-Path $PSScriptRoot '*.pas') (Join-Path $scratch 'src')
$db = Join-Path $scratch 'unusedglobal.sqlite'

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
function LineOf([string]$Marker) {
  $m = @(Select-String -LiteralPath $fixture -SimpleMatch -Pattern "// $Marker")
  if ($m.Count -ne 1) { throw "marker '$Marker' found $($m.Count) times in the fixture" }
  return [int]$m[0].LineNumber
}
function At($Set, [int]$L) { return @($Set | Where-Object { [int]$_.start_line -eq $L -and (Split-Path $_.file_path -Leaf) -eq 'uUnusedGlobal.pas' }) }

& $exePath index (Join-Path $scratch 'src') --db $db 2>&1 | Out-Null
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

$triggers = @('TRIGGER-INTF-CONST', 'TRIGGER-INTF-VAR', 'TRIGGER-INTF-TYPE', 'TRIGGER-IMPL-CONST',
              'TRIGGER-IMPL-VAR', 'TRIGGER-IMPL-TYPE', 'TRIGGER-IMPL-RECORD')
$controls = @('CONTROL-INTF-OTHERUNIT', 'CONTROL-INTF-OWNIMPL', 'CONTROL-INTF-CLASS', 'CONTROL-IMPL-NESTED',
              'CONTROL-IMPL-INIT', 'CONTROL-IMPL-VIATYPED', 'CONTROL-IMPL-READ', 'CONTROL-IMPL-VARREAD',
              'CONTROL-IMPL-RECUSED')

# RUN 1 -- default lint-all: ON by default
$all = Parse-Findings (& $exePath lint-all --db $db --format json 2>$null)
Check 'run 1 is not vacuous (lint-all returned findings)' ($all.Count -gt 0) "total=$($all.Count)"
$a = @($all | Where-Object { $_.rule -eq $Rule })
$a | ForEach-Object { Write-Host ("    {0}:{1} {2}" -f (Split-Path $_.file_path -Leaf), $_.start_line, $_.message) }
Check 'run 1 ON by default: exactly 7 findings' ($a.Count -eq 7) "count=$($a.Count)"
foreach ($t in $triggers) { $l = LineOf $t; Check "$t fires" ((At $a $l).Count -eq 1) "line=$l" }
foreach ($c in $controls) { $l = LineOf $c; Check "$c stays silent" ((At $a $l).Count -eq 0) "line=$l" }

# RUN 2 -- --rule narrows to the rule; --disable turns it off
$r2 = Parse-Findings (& $exePath lint-all --db $db --format json --rule $Rule 2>$null)
Check 'run 2 --rule: same 7 findings' (@($r2 | Where-Object { $_.rule -eq $Rule }).Count -eq 7)
$r2d = Parse-Findings (& $exePath lint-all --db $db --format json --disable $Rule 2>$null)
Check 'run 2 --disable: no finding of the rule' (@($r2d | Where-Object { $_.rule -eq $Rule }).Count -eq 0) "total=$($r2d.Count)"

# RUN 3 -- positive control: remove each lone use (same line count) and the symbol fires
function Swap([string]$File, [string]$Old, [string]$New) {
  $t = [IO.File]::ReadAllText($File)
  Check "fixture spells '$Old'" ($t.Contains($Old))
  [IO.File]::WriteAllText($File, $t.Replace($Old, $New), [Text.Encoding]::ASCII)
}
$sc = Join-Path $scratch 'src\uUnusedGlobal.pas'
Swap $sc 'VImplUsed:= CImplNested;' 'VImplUsed:= 0;'
Swap $sc 'VImplUsed:= CImplInit;' 'VImplUsed:= 0;'
Swap $sc '(CBase, 6)' '(5, 6)'
Swap (Join-Path $scratch 'src\uUnusedGlobalUser.pas') 'N:= GIntfOtherUnit;' 'N:= 0;'
& $exePath index (Join-Path $scratch 'src') --db $db 2>&1 | Out-Null
$r3 = Parse-Findings (& $exePath lint-all --db $db --format json --rule $Rule 2>$null)
$c3 = @($r3 | Where-Object { $_.rule -eq $Rule })
foreach ($c in @('CONTROL-IMPL-NESTED', 'CONTROL-IMPL-INIT', 'CONTROL-IMPL-VIATYPED', 'CONTROL-INTF-OTHERUNIT')) {
  Check "run 3 lone use removed -> $c fires" ((At $c3 (LineOf $c)).Count -eq 1)
}
Check 'run 3 still-used symbols stay silent' ((At $c3 (LineOf 'CONTROL-IMPL-READ')).Count -eq 0 -and (At $c3 (LineOf 'CONTROL-INTF-OWNIMPL')).Count -eq 0)
}
finally {
  if (Test-Path $scratch) { try { [System.IO.Directory]::Delete($scratch, $true) } catch { } }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'; exit 0