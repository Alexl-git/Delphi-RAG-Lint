<#
  run_unused_enum_value.ps1 -- the `unused-enum-value` project lint rule
  (lane B-ENUM; INBOX-lint-rules-from-new-facts-2026-09-23.md rule 2).

  An enum value no ref names fires, per value, at its declaration -- but only in
  a type that (1) has at least one NAMED value and (2) shows no implicit use
  (Low/High, Succ/Pred/Inc/Dec, a cast TEnum(x), an ordinal cast Ord(v),
  RTTI, a property of the type).

    RUN 1  lint-all (rule ON by default)           -> exactly the TRIGGER values; the type-level dl:ok on TTypeMarked silences its values and is not called unused; the one on TAllUsed is
    RUN 2  lint-all --rule / --disable              -> the same TRIGGER values / none,
                                                       none of the CONTROL ones
    RUN 3  scratch copy with the Low/High loop and the type marker removed -> TIterated's itB and TTypeMarked's two values now
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

$triggers = @('TRIGGER-UNUSED', 'TRIGGER-ALSO', 'TRIGGER-SPARE')
$controls = @('CONTROL-READ', 'CONTROL-LOWHIGH', 'CONTROL-CAST', 'CONTROL-ORD', 'CONTROL-SUCC', 'CONTROL-PROP', 'CONTROL-NONE',
              'CONTROL-TYPEMARK-A', 'CONTROL-TYPEMARK-B', 'CONTROL-FILLER-0', 'CONTROL-FILLER-1')
function LineOfText([string]$Text) {
  $m = @(Select-String -LiteralPath $fixture -SimpleMatch -Pattern $Text)
  if ($m.Count -ne 1) { throw "text '$Text' found $($m.Count) times in the fixture" }
  return [int]$m[0].LineNumber
}
$markedLine = LineOfText 'TTypeMarked = ('
$allUsedLine = LineOfText 'TAllUsed = ('

# RUN 1 -- default lint-all: the rule is ON by default (ENUMRULES 2026-10-28)
$all = Parse-Findings (& $exePath lint-all --db $db --format json 2>$null)
Check 'run 1 is not vacuous (lint-all returned findings)' ($all.Count -gt 0) "total=$($all.Count)"
$a = @($all | Where-Object { $_.rule -eq $Rule })
$a | ForEach-Object { Write-Host ("    {0}:{1} {2}" -f (Split-Path $_.file_path -Leaf), $_.start_line, $_.message) }
Check 'run 1 ON by default: exactly 3 findings' ($a.Count -eq 3) "count=$($a.Count)"
foreach ($t in $triggers) { $l = LineOf $t; Check "$t fires" ((At $a $l).Count -eq 1) "line=$l" }
Check 'message names the type and value' ((@(At $a (LineOf 'TRIGGER-UNUSED'))[0].message) -like '*TMixed.mxUnused*')
foreach ($c in $controls) { $l = LineOf $c; Check "$c stays silent" ((At $a $l).Count -eq 0) "line=$l" }
# the type-level marker: used (not review-marker-unused), and its no-@hash hint is ONE per marker, not one per value
$unused = @($all | Where-Object { $_.rule -eq 'review-marker-unused' })
Check 'type-level marker is NOT reported unused' ((At $unused $markedLine).Count -eq 0) "line=$markedLine"
Check 'positive control: a type marker with nothing to suppress IS reported unused' ((At $unused $allUsedLine).Count -eq 1) "line=$allUsedLine"
$stale = @($all | Where-Object { $_.rule -eq 'review-marker-stale' })
Check 'unhashed type marker: exactly one no-@hash hint, on the type line' ((At $stale $markedLine).Count -eq 1) "count=$((At $stale $markedLine).Count)"

# RUN 2 -- --rule narrows to the rule; --disable turns it off
$r2 = Parse-Findings (& $exePath lint-all --db $db --format json --rule $Rule 2>$null)
Check 'run 2 --rule: same 3 findings' (@($r2 | Where-Object { $_.rule -eq $Rule }).Count -eq 3)
$r2d = Parse-Findings (& $exePath lint-all --db $db --format json --disable $Rule 2>$null)
Check 'run 2 --disable: no finding of the rule' (@($r2d | Where-Object { $_.rule -eq $Rule }).Count -eq 0) "total=$($r2d.Count)"
# RUN 3 -- positive control: drop the Low/High loop (same line count) and itB fires
$sc = Join-Path $scratch 'src\uUnusedEnum.pas'
$txt = [IO.File]::ReadAllText($sc)
$loop = 'for I:= Low(TIterated) to High(TIterated) do N:= N + 1;'
Check 'fixture spells the Low/High loop' ($txt.Contains($loop))
$markText = '// dl:ok unused-enum-value -- REVIEWED 2026-10-28 values mirror stored ordinals'
Check 'fixture spells the type marker' ($txt.Contains($markText))
[IO.File]::WriteAllText($sc, $txt.Replace($loop, 'N:= N + 1;').Replace($markText, '// marker removed'), [Text.Encoding]::ASCII)
& $exePath index (Join-Path $scratch 'src') --db $db 2>&1 | Out-Null
$r3 = Parse-Findings (& $exePath lint-all --db $db --format json --rule $Rule 2>$null)
$c3 = @($r3 | Where-Object { $_.rule -eq $Rule })
Check 'run 3 Low/High removed -> TIterated.itB fires' ((At $c3 (LineOf 'CONTROL-LOWHIGH')).Count -eq 1) "count=$($c3.Count)"
Check 'run 3 type marker removed -> tmUnusedA fires' ((At $c3 (LineOf 'CONTROL-TYPEMARK-A')).Count -eq 1)
Check 'run 3 type marker removed -> tmUnusedB fires' ((At $c3 (LineOf 'CONTROL-TYPEMARK-B')).Count -eq 1)
Check 'run 3 fillers stay silent without any marker' ((At $c3 (LineOf 'CONTROL-FILLER-0')).Count -eq 0)
}
finally {
  if (Test-Path $scratch) { try { [System.IO.Directory]::Delete($scratch, $true) } catch { } }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'; exit 0
