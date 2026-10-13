<#
  run_diaglist_harness.ps1 -- pins DragLint.Plugin.DiagList, the ordering /
  nearest-row / clipboard helpers behind the Structure panel's Diagnostics rows.

  THE DEFECTS THIS PINS (owner report 2026-10-13, ORM3 BASICS.PAS):
    * "Copy All Diagnostics" walked the raw cache order (rule-grouped) while the
      panel showed line order -- the paste did not match the screen.
    * Caret follow only lit a row on an EXACT line; between findings nothing
      was selected. It now picks the nearest row.
  Copy-selected and the "Fix all" enablement use the same helpers.

  The fixture is fed in RULE-GROUPED order on purpose: if DiagDisplayOrder
  returned the identity permutation, O1 fails -- which is the old copy order.

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param(
  [string]$FixtureDir = "$PSScriptRoot\fixtures\diaglist",
  [string]$WorkDir    = "$env:TEMP\drag-lint-diaglist-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
Write-Host '== DiagList: panel order, nearest row, clipboard text ==' -ForegroundColor Cyan
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

# a bare .dpr cannot be built by msbuild, so use dcc64 from rsvars (as run_hover_callers_scope_guard.ps1)
$rsvars    = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$pluginDir = "$PSScriptRoot\..\..\src\delphi-plugin"
$outDir    = "$FixtureDir\Win64\Debug"
New-Item -ItemType Directory -Force $outDir | Out-Null
$batPath = "$WorkDir\build_harness.bat"
$logPath = "$WorkDir\build_harness.log"
$batBody = (@(
  '@echo off'
  "call `"$rsvars`""
  "cd /d `"$FixtureDir`""
  "dcc64 -CC -U`"$pluginDir`" -E`"$outDir`" -N0`"$outDir`" DiagListHarness.dpr"
  'echo BUILD_EXITCODE=%ERRORLEVEL%'
) -join "`r`n")
[System.IO.File]::WriteAllText($batPath, $batBody, [System.Text.Encoding]::ASCII)
$null = Start-Process cmd.exe -ArgumentList "/c", "`"$batPath`"" `
          -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" -NoNewWindow -Wait -PassThru
$log = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
$buildOk = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:')
Check 'DiagListHarness.dpr builds (Win64 Debug)' $buildOk (($log -split "`r?`n" | Select-Object -Last 4) -join ' | ')
$exe = "$outDir\DiagListHarness.exe"
if (-not $buildOk -or -not (Test-Path $exe)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

$out = & $exe 2>&1 | Out-String
$kv = @{}
foreach ($line in ($out -split "`r?`n")) { if ($line -match '^([A-Za-z0-9_.]+)=(.*)$') { $kv[$matches[1]] = $matches[2] } }
Check 'harness ran to completion' ($out -match '(?m)^DONE') ''

Write-Host '-- order (panel rows AND clipboard)' -ForegroundColor Cyan
Check 'O1 order is by (line, col, index), not the rule-grouped input order' ($kv['order'] -eq '1,4,3,2,0') "got: $($kv['order'])"
Check 'O2 lines read top-to-bottom'                                      ($kv['lines'] -eq '10,10,11,227,227') "got: $($kv['lines'])"

Write-Host '-- nearest row for the caret' -ForegroundColor Cyan
Check 'N1 exact line -> first row on it'       ($kv['near.exact10'] -eq '0')  "got: $($kv['near.exact10'])"
Check 'N2 exact line 11 -> its row'            ($kv['near.exact11'] -eq '2')  "got: $($kv['near.exact11'])"
Check 'N3 caret above every finding -> first'  ($kv['near.before']  -eq '0')  "got: $($kv['near.before'])"
Check 'N4 caret below every finding -> first row of the last line' ($kv['near.after'] -eq '3') "got: $($kv['near.after'])"
Check 'N5 caret in a gap -> nearer row (11 beats 227 from 100)'    ($kv['near.mid'] -eq '2')   "got: $($kv['near.mid'])"
Check 'N6 equal distance -> the row ABOVE'     ($kv['near.tie']   -eq '0')  "got: $($kv['near.tie'])"
Check 'N7 no rows -> -1'                       ($kv['near.empty'] -eq '-1') "got: $($kv['near.empty'])"
Check 'N8 non-positive line -> -1'             ($kv['near.zero']  -eq '-1') "got: $($kv['near.zero'])"

Write-Host '-- clipboard text' -ForegroundColor Cyan
Check 'C1 one row format'                       ($kv['line0'] -eq '[W] (10:5) uu ShellAPI  [unused-unit-in-uses]') "got: $($kv['line0'])"
Check 'C2 header + 5 rows'                      ($kv['text.lines'] -eq '6') "got: $($kv['text.lines'])"
Check 'C3 first row after header is line 10'    ($kv['text.first'] -eq $kv['line0']) "got: $($kv['text.first'])"
Check 'C4 last row is the last line'            ($kv['text.last'] -eq '[I] (227:7) pf A  [public-field]') "got: $($kv['text.last'])"
Check 'C5 ends in CRLF'                          ($kv['text.crlfend'] -eq 'TRUE') ''
Check 'C6 a selection copies only its rows, no header when none given' ($kv['text.sel'] -eq '[W] (11:5) uu ShlObj  [unused-unit-in-uses]') "got: $($kv['text.sel'])"
Check 'C7 nothing emitted -> empty text (no lone header)' ($kv['text.none'] -eq '[]') "got: $($kv['text.none'])"

Write-Host '-- Fix all enablement' -ForegroundColor Cyan
Check 'F1 two fixable findings counted (rule-id compared case-insensitively)' ($kv['fix.two'] -eq '2') "got: $($kv['fix.two'])"
Check 'F2 no fixable rule -> 0 (item disabled)' ($kv['fix.no']    -eq '0') "got: $($kv['fix.no'])"
Check 'F3 no findings -> 0'                     ($kv['fix.empty'] -eq '0') "got: $($kv['fix.empty'])"

Write-Host '-- content signature (panel refresh trigger)' -ForegroundColor Cyan
Check 'S1 equal sets -> equal signature'          ($kv['sig.same']      -eq 'TRUE') ''
Check 'S2 same COUNT, changed message -> differs' ($kv['sig.msg']       -eq 'TRUE') ''
Check 'S3 same COUNT, changed line -> differs'    ($kv['sig.line']      -eq 'TRUE') ''
Check 'S4 empty vs non-empty -> differs'          ($kv['sig.emptydiff'] -eq 'TRUE') ''

Write-Host '-- autofix summary (what Fix all reports back)' -ForegroundColor Cyan
Check 'A1 applied line extracted'        ($kv['af.applied'] -eq 'applied 2 edit(s) across 1 file(s) (.bak written)') "got: $($kv['af.applied'])"
Check 'A2 nothing-fixable line extracted' ($kv['af.none'] -eq 'no fixable findings (of 14 finding(s))') "got: $($kv['af.none'])"
Check 'A3 no summary -> empty'           ($kv['af.missing'] -eq '[]') "got: $($kv['af.missing'])"
Check 'A4 applied N>0 -> True'           ($kv['af.isapplied']   -eq 'TRUE')  ''
Check 'A5 applied 0 -> False'            ($kv['af.zero']        -eq 'FALSE') ''
Check 'A6 nothing fixable -> False'      ($kv['af.noneapplied'] -eq 'FALSE') ''
Check 'A7 a summary split INTO a stderr note is still found (the IDE reported nothing, 2026-10-13)' `
  ($kv['af.interleaved'] -eq 'no fixable findings (of 147 finding(s))') "got: $($kv['af.interleaved'])"
Check 'A8 the not-opted-in naming rules are read from the engine note' ($kv['af.optout'] -eq 'const-casing, type-name-prefix') "got: $($kv['af.optout'])"
Check 'A9 ... and no note means none'    ($kv['af.nooptout'] -eq '[]') "got: $($kv['af.nooptout'])"

Write-Host '-- Fix it on unused-unit-in-uses (uses-fix)' -ForegroundColor Cyan
Check 'U1 the unit name is read from the finding'     ($kv['uu.name'] -eq 'System.Win.Registry') "got: $($kv['uu.name'])"
Check 'U2 another rule''s message yields no unit'      ($kv['uu.other'] -eq '[]') "got: $($kv['uu.other'])"
Check 'U3 a verified remove is reported as applied (unit compared case-insensitively)' `
  ($kv['uf.remove'] -eq 'applied 1 edit(s): system.win.registry removed (.bak written)') "got: $($kv['uf.remove'])"
Check 'U4 a verified move says where it went'          ($kv['uf.move'] -eq 'applied 1 edit(s): System.IniFiles moved to the implementation section (.bak written)') "got: $($kv['uf.move'])"
Check 'U5 a skipped unit says why, and is not applied' ($kv['uf.skip'] -eq 'no change: System.SysUtils -- moving it did not verify') "got: $($kv['uf.skip'])"
Check 'U6 a unit not in the document is a no-change'   ($kv['uf.absent'] -eq 'no change: Vcl.Nothing -- not in this unit''s uses clause') "got: $($kv['uf.absent'])"
Check 'U7 no JSON at all -> empty (caller reports the failure)' ($kv['uf.nojson'] -eq '[]') "got: $($kv['uf.nojson'])"
Check 'U8 the shared completion path sees a move as applied'  ($kv['uf.applied'] -eq 'TRUE') ''
Check 'U9 ... and a skip as not applied'                      ($kv['uf.notapplied'] -eq 'FALSE') ''

[System.IO.Directory]::Delete($WorkDir, $true)
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }