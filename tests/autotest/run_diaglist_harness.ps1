<#
  run_diaglist_harness.ps1 -- pins DragLint.Plugin.DiagList, the ordering /
  nearest-row / clipboard helpers behind the Structure panel's Diagnostics rows.

  THE DEFECTS THIS PINS (owner report 2026-10-13, ORM3 BASICS.PAS):
    * "Copy All Diagnostics" walked the raw cache order (rule-grouped) while the
      panel showed line order -- the paste did not match the screen.
    * Caret follow only lit a row on an EXACT line; between findings nothing
      was selected. It now picks the nearest row.
  Copy-selected and the "Fix all" enablement use the same helpers.
  R1-R39 pin the multi-project rename preview parser, the apply/confirm/refuse
  decision and the confirmation text (spec 2026-10-13-multi-project-rename,
  criteria 16-19).

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

Write-Host '-- multi-project rename preview (spec criteria 16-19)' -ForegroundColor Cyan
# RenamePreviewAction ordinals: 0 = apply now, 1 = confirm first, 2 = refuse
Check 'R1 owners read from rename-owners'      ($kv['rp.owners'] -eq '4')  "got: $($kv['rp.owners'])"
Check 'R2 probed read from "of N indexes"'     ($kv['rp.probed'] -eq '37') "got: $($kv['rp.probed'])"
Check 'R3 four project lines (2 rename-project + 2 named only in the apply counts)' ($kv['rp.projects'] -eq '4') "got: $($kv['rp.projects'])"
Check 'R4 project line shape'                  ($kv['rp.project0'] -eq 'Micronite2027 -- index fresh, 0 reference(s)') "got: $($kv['rp.project0'])"
Check 'R5 reindexed state carried'             ($kv['rp.project1'] -eq 'MicroniteMW1Service -- index reindexed, 0 reference(s)') "got: $($kv['rp.project1'])"
Check 'R6 a project only in the counts says its index state was not reported' ($kv['rp.project2'] -eq 'DMTEST -- index not reported, 0 reference(s)') "got: $($kv['rp.project2'])"
Check 'R7 no refusal in a plain preview'       ($kv['rp.refused'] -eq '[]') "got: $($kv['rp.refused'])"
Check 'R8 old/new from the first applied target' (($kv['rp.old'] -eq 'LotNotes_Headline') -and ($kv['rp.new'] -eq 'LotNotesHeadline')) "got: $($kv['rp.old']) -> $($kv['rp.new'])"
Check 'R9 one applied rename'                  ($kv['rp.renames'] -eq '1') "got: $($kv['rp.renames'])"
Check 'R10 dropped target with its reason'     ($kv['rp.dropped0'] -eq 'L40 Foo_Bar -> FooBar: project MicroniteMW1Service: name FooBar already declared in uX') "got: $($kv['rp.dropped0'])"
Check 'R11 rename-unknown kept as text'        ($kv['rp.unknown0'] -eq 'C:\x\X.sqlite: database disk image is malformed') "got: $($kv['rp.unknown0'])"
Check 'R12 4 owners -> confirm first (criterion 16)' ($kv['rp.action'] -eq '1') "got: $($kv['rp.action'])"
Check 'R13 confirmation says only indexed projects were checked (criterion 19)' ($kv['rc.notindexed'] -eq 'TRUE') ''
Check 'R14 confirmation names every owning project' ($kv['rc.allnames'] -eq 'TRUE') ''
Check 'R15 confirmation names the rename and the unit' ($kv['rc.header'] -eq 'TRUE') ''
Check 'R16 confirmation lists the dropped target'  ($kv['rc.dropped'] -eq 'TRUE') ''
Check 'R17 confirmation lists the unknown index'   ($kv['rc.unknown'] -eq 'TRUE') ''
Check 'R18 confirmation gives owners and indexes checked' ($kv['rc.counts'] -eq 'TRUE') ''
Check 'R19 refusal text after "rename refused -- "' ($kv['rr.refused'] -eq 'project MicroniteMW1Service: name MyConst already declared in uB') "got: $($kv['rr.refused'])"
Check 'R20 a refusal -> refuse, nothing applied (criterion 18)' ($kv['rr.action'] -eq '2') "got: $($kv['rr.action'])"
Check 'R21 single-project output -> owners=0'      ($kv['rs.owners'] -eq '0') "got: $($kv['rs.owners'])"
Check 'R22 ... no project lines'                   ($kv['rs.projects'] -eq '0') "got: $($kv['rs.projects'])"
Check 'R23 ... apply at once, as before'           ($kv['rs.action'] -eq '0') "got: $($kv['rs.action'])"
Check 'R24 a tag split into a stderr note is still read' (($kv['rx.owners'] -eq '3') -and ($kv['rx.probed'] -eq '5')) "got: $($kv['rx.owners']) of $($kv['rx.probed'])"
Check 'R25 references summed over every applied target' ($kv['rx.project0'] -eq 'A -- index fresh, 3 reference(s)') "got: $($kv['rx.project0'])"
Check 'R26 a rename-project reason suffix is kept' ($kv['rx.project1'] -eq 'B -- index unverified (reindex failed: exit 2), 2 reference(s)') "got: $($kv['rx.project1'])"
Check 'R27 a library owner line'                   ($kv['rx.project2'] -eq 'LIB -- index library, 0 reference(s)') "got: $($kv['rx.project2'])"
Check 'R28 every applied rename listed'            ($kv['rx.renames'] -eq 'My_Const -> MyConst|Other_Const -> OtherConst') "got: $($kv['rx.renames'])"
Check 'R29 ... and the confirmation lists both'    ($kv['rx.multi'] -eq 'TRUE') ''
Check 'R30 3 owners -> confirm'                    ($kv['rx.action'] -eq '1') "got: $($kv['rx.action'])"
Check 'R31 "0 of 0" (manifest did not load) read'  ($kv['rm.owners'] -eq '0') "got: $($kv['rm.owners'])"
Check 'R32 free-text rename-unknown kept whole'    ($kv['rm.unknown0'] -eq 'manifest did not load completely: C:\x\drag-lint.json: Unexpected character') "got: $($kv['rm.unknown0'])"
Check 'R33 0 owners + refusal -> refuse, NOT apply' ($kv['rm.action'] -eq '2') "got: $($kv['rm.action'])"
Check 'R34 0 owners + unknown, no refusal (batch) -> confirm, NOT apply' ($kv['rb.action'] -eq '1') "got: $($kv['rb.action'])"
Check 'R35 apply run: the refusal is the Diagnostics summary (last autofix: line)' ($kv['ra.summary'] -eq 'rename refused -- project B: uB.pas:7 changed since it was indexed') "got: $($kv['ra.summary'])"
Check 'R36 ... which by itself reads as not applied' ($kv['ra.summaryapplied'] -eq 'FALSE') ''
Check 'R37 ... but the earlier applied line is seen, so the buffer is reloaded' ($kv['ra.anyapplied'] -eq 'TRUE') ''
Check 'R38 rename-dropped-at-write is parsed'      ($kv['ra.dropped0'] -eq 'My_Const -> MyConst C:\w\B\uB.pas:7 (stale)') "got: $($kv['ra.dropped0'])"
Check 'R39 applied 0 -> nothing to reload'         ($kv['ra.noneapplied'] -eq 'FALSE') ''
Check 'R40 80 applied renames parsed'               ($kv['cap.renames'] -eq '80') "got: $($kv['cap.renames'])"
Check 'R41 the confirmation lists the first 10 renames' (($kv['cap.tenth'] -eq 'TRUE') -and ($kv['cap.eleventh'] -eq 'FALSE')) "got: $($kv['cap.tenth'])/$($kv['cap.eleventh'])"
Check 'R42 ... then "... and 70 more"'              ($kv['cap.more'] -eq 'TRUE') ''
Check 'R43 dropped list capped the same way (10 + "... and 5 more")' ($kv['cap.dropmore'] -eq 'TRUE') ''
Check 'R44 project lines stay complete'             ($kv['cap.projects'] -eq 'TRUE') ''
Check 'R45 rename-local: N read'                     ($kv['rl.count'] -eq '3') "got: $($kv['rl.count'])"
Check 'R46 single-project renames -> confirm (local) before applying' ($kv['rl.action'] -eq '3') "got: $($kv['rl.action'])"
Check 'R47 local confirmation text'                  ($kv['rl.text'] -eq 'Rename 3 identifier(s) in Micronite2027?') "got: $($kv['rl.text'])"
Check 'R48 rename-local: 0 -> apply as before'       ($kv['rl.zero'] -eq '0') "got: $($kv['rl.zero'])"
Check 'R49 2 owners with rename-local: 0 -> the multi-project confirm' ($kv['rl.multi'] -eq '1') "got: $($kv['rl.multi'])"
Check 'R50 index=stale owners counted once per project (Ruling 12)' ($kv['st.stale'] -eq '1') "got: $($kv['st.stale'])"
Check 'R51 rename-unindexed read, one entry per section (Ruling 14)' ($kv['st.unindexed'] -eq 'DMTEST (C:\x\DMTEST.sqlite)') "got: $($kv['st.unindexed'])"
Check 'R52 a stale project line keeps its changed-file count' ($kv['st.project1'] -eq 'B -- index stale (2 changed file(s)), 1 reference(s)') "got: $($kv['st.project1'])"
Check 'R53 confirmation warns that stale indexes are reindexed before writing' ($kv['st.staletext'] -eq 'TRUE') ''
Check 'R54 confirmation names the configured project that has no index' ($kv['st.unindexedtext'] -eq 'TRUE') ''
Check 'R55 no stale owner -> no reindex warning' ($kv['st.nostale'] -eq 'FALSE') ''
Check 'R56 rename-unindexed turns a single-project fix into a confirm (owner 2026-10-14)' ($kv['st.singleaction'] -eq '1') "got: $($kv['st.singleaction'])"
Check 'R57 single-owner confirm names every unindexed section' ($kv['un.text'] -eq 'TRUE') ''
Check 'R58 single-owner confirm does not claim 0 owners / 0 renames' ($kv['un.noowners'] -eq 'FALSE') ''
Check 'R59 no rename-unindexed -> single-owner fix applies as before' ($kv['un.plain'] -eq '0') "got: $($kv['un.plain'])"
Check 'R60 refusal + rename-unindexed -> refuse' ($kv['un.refuse'] -eq '2') "got: $($kv['un.refuse'])"
Check 'R61 Fix all (rename-local) + rename-unindexed -> the unindexed confirm' ($kv['un.local'] -eq '1') "got: $($kv['un.local'])"
Check 'R62 unindexed section list capped at 10' ($kv['un.cap'] -eq 'TRUE') ''
# tm: INBOX rename-owner-without-target-reports-fresh -- the engine's two new reasons, no plugin change
Check 'R63 a tag-mismatch owner keeps its unverified reason verbatim' ($kv['tm.project1'] -eq 'C -- index unverified (index was built from project A, not C.dproj -- rebuild it: drag-lint index --project C:\w\C\C.dproj --db C:\w\C.sqlite --rebuild), 0 reference(s)') "got: $($kv['tm.project1'])"
Check 'R64 a missing-member owner keeps its stale reason verbatim' ($kv['tm.project2'] -eq 'E -- index stale (1 project member(s) not in the index: C:\w\E\uLate.pas), 0 reference(s)') "got: $($kv['tm.project2'])"
Check 'R65 ... and counts as stale (unverified does not)' ($kv['tm.stale'] -eq '1') "got: $($kv['tm.stale'])"
Check 'R66 ... and the refusal wins -> refuse' ($kv['tm.action'] -eq '2') "got: $($kv['tm.action'])"

# ta: B-19 -- the rename apply's timeout covers the reindex of every stale owner
Check 'R67 one stale owner adds one reindex budget to the apply timeout' ($kv['ta.stale1'] -eq '660000') "got: $($kv['ta.stale1'])"
Check 'R68 no deadline stays no deadline' ($kv['ta.nodeadline'] -eq '0') "got: $($kv['ta.nodeadline'])"
Check 'R69 no stale owner -> the fix''s own timeout' ($kv['ta.fresh'] -eq '60000') "got: $($kv['ta.fresh'])"
[System.IO.Directory]::Delete($WorkDir, $true)
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }