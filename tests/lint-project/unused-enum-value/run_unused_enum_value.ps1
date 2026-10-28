<#
  run_unused_enum_value.ps1 -- the `unused-enum-value` project lint rule
  (lane B-ENUM; INBOX-lint-rules-from-new-facts-2026-09-23.md rule 2).

  An enum value no ref names fires, per value, at its declaration -- but only in
  a type that (1) has at least one NAMED value and (2) shows no implicit use
  (Low/High, Succ/Pred/Inc/Dec, a cast TEnum(x), an ordinal cast Ord(v),
  RTTI, a property of the type).

    RUN 1  lint-all (rule OFF by default)          -> no finding of the rule
    RUN 2  lint-all --rule unused-enum-value        -> exactly the TRIGGER values,
                                                       none of the CONTROL ones
    RUN 3  scratch copy with the Low/High loop removed -> TIterated's itB now
           fires (positive control: the implicit use drives the silence)

  Line numbers come from the fixture's TRIGGER-* / CONTROL-* markers.
  `lint --json` is a BARE ARRAY whose line key is `start_line`.

  Usage: pwsh -File tests\lint-project\unused-enum-value\run_unused_enum_value.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$fixture = Join-Path $PSScriptRoot 'uUnusedEnum.pas'
$scratch = Join-Path C:\TEMP "draglint_unused_enum_value_$PID"
$Rule    = 'unused-enum-value'
try {
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path (Join-Path $scratch 'src') | Out-Null
Copy-Item $fixture (Join-Path $scratch 'src')
$db = Join-Path $scratch 'unusedenum.sqlite'

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
function At($Set, [int]$L) { return @($Set | Where-Object { [int]$_.start_line -eq $L }) }

& $exePath index (Join-Path $scratch 'src') --db $db 2>&1 | Out-Null
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

$triggers = @('TRIGGER-UNUSED', 'TRIGGER-ALSO')
$controls = @('CONTROL-READ', 'CONTROL-LOWHIGH', 'CONTROL-CAST', 'CONTROL-ORD', 'CONTROL-SUCC', 'CONTROL-PROP', 'CONTROL-NONE')

# RUN 1 -- default lint-all: the rule is OFF by default
$all = Parse-Findings (& $exePath lint-all --db $db --format json 2>$null)
Check 'run 1 is not vacuous (lint-all returned findings)' ($all.Count -gt 0) "total=$($all.Count)"
Check 'run 1 OFF by default: no finding of the rule' (@($all | Where-Object { $_.rule -eq $Rule }).Count -eq 0)

# RUN 2 -- opted in
$r2 = Parse-Findings (& $exePath lint-all --db $db --format json --rule $Rule 2>$null)
$a = @($r2 | Where-Object { $_.rule -eq $Rule })
$a | ForEach-Object { Write-Host ("    {0}:{1} {2}" -f (Split-Path $_.file_path -Leaf), $_.start_line, $_.message) }
Check 'run 2 exactly 2 findings' ($a.Count -eq 2) "count=$($a.Count)"
foreach ($t in $triggers) { $l = LineOf $t; Check "$t fires" ((At $a $l).Count -eq 1) "line=$l" }
Check 'message names the type and value' ((@(At $a (LineOf 'TRIGGER-UNUSED'))[0].message) -like '*TMixed.mxUnused*')
foreach ($c in $controls) { $l = LineOf $c; Check "$c stays silent" ((At $a $l).Count -eq 0) "line=$l" }

# RUN 3 -- positive control: drop the Low/High loop (same line count) and itB fires
$sc = Join-Path $scratch 'src\uUnusedEnum.pas'
$txt = [IO.File]::ReadAllText($sc)
$loop = 'for I:= Low(TIterated) to High(TIterated) do N:= N + 1;'
Check 'fixture spells the Low/High loop' ($txt.Contains($loop))
[IO.File]::WriteAllText($sc, $txt.Replace($loop, 'N:= N + 1;'), [Text.Encoding]::ASCII)
& $exePath index (Join-Path $scratch 'src') --db $db 2>&1 | Out-Null
$r3 = Parse-Findings (& $exePath lint-all --db $db --format json --rule $Rule 2>$null)
$c3 = @($r3 | Where-Object { $_.rule -eq $Rule })
Check 'run 3 Low/High removed -> TIterated.itB fires' ((At $c3 (LineOf 'CONTROL-LOWHIGH')).Count -eq 1) "count=$($c3.Count)"
}
finally {
  if (Test-Path $scratch) { try { [System.IO.Directory]::Delete($scratch, $true) } catch { } }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'; exit 0
