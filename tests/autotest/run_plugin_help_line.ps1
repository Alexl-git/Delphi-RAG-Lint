<#
  run_plugin_help_line.ps1 -- pins the pure half of the IDE help line
  (spec docs\superpowers\specs\2026-10-23-ide-help-line-design.md, plan
  docs\superpowers\plans\2026-10-23-ide-help-line.md).

  WHAT IT PINS
    U  help-root URL rules (DragLint.Plugin.HelpIndex): web and file: roots,
       a plain folder, trailing slashes, the default root; HelpRoot settings
       round-trip incl. empty -> default (test registry root only).

  Builds tests\autotest\fixtures\helpline\HelpLineHarness.dpr with dcc64 and
  -DDRAGLINT_TEST_REGROOT into a per-run scratch folder, removed in `finally`.
  Exit 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param(
  [string]$WorkDir = "$env:TEMP\drag-lint-help-line-$PID",
  [string]$Rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Rsvars)) { Write-Host "SKIP: no rsvars.bat ($Rsvars)" -ForegroundColor Yellow; exit 0 }

$harnessDir = "$PSScriptRoot\fixtures\helpline"
$pluginDir  = (Resolve-Path "$PSScriptRoot\..\..\src\delphi-plugin").Path
$coreDir    = (Resolve-Path "$PSScriptRoot\..\..\src\core").Path

Write-Host '== IDE help line: URL rules, feature list, matcher, queue text ==' -ForegroundColor Cyan
try {
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory $WorkDir | Out-Null

  $batPath = "$WorkDir\build_harness.bat"
  $logPath = "$WorkDir\build_harness.log"
  $batBody = (@(
    '@echo off'
    "call `"$Rsvars`""
    "cd /d `"$harnessDir`""
    "dcc64 -CC -DDRAGLINT_TEST_REGROOT -U`"$pluginDir;$coreDir`" -E`"$WorkDir`" -N0`"$WorkDir`" HelpLineHarness.dpr"
    'echo BUILD_EXITCODE=%ERRORLEVEL%'
  ) -join "`r`n")
  [IO.File]::WriteAllText($batPath, $batBody, [Text.Encoding]::ASCII)
  $null = Start-Process cmd.exe -ArgumentList '/c', "`"$batPath`"" `
            -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" -NoNewWindow -Wait -PassThru
  $log = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
  $buildOk = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:')
  Check 'HelpLineHarness.dpr builds (Win64)' $buildOk ((($log -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 4) -join ' | ')
  $exe = "$WorkDir\HelpLineHarness.exe"
  if (-not $buildOk -or -not (Test-Path $exe)) { throw 'harness did not build' }

  $scratch = "$WorkDir\scratch"
  New-Item -ItemType Directory $scratch | Out-Null
  $out = & $exe $harnessDir $scratch 2>&1 | Out-String
  $kv = @{}
  foreach ($line in ($out -split "`r?`n")) { if ($line -match '^([A-Za-z0-9_.]+)=(.*)$') { $kv[$matches[1]] = $matches[2] } }
  Check 'harness ran to completion' ($out -match '(?m)^DONE') $out
  function Eq($name, $key, $want) { Check $name ($kv[$key] -ceq $want) "want: $want | got: $($kv[$key])" }

  Write-Host '-- U: help root + URL rules' -ForegroundColor Cyan
  $site = 'https://www.delphi-rag-lint.com'
  Eq 'U1 web root: <root>/help/dl/features/<id>/'            'url.web'       "$site/help/dl/features/ask/"
  Eq 'U2 a trailing slash on the root gives the same URL'      'url.webslash'  "$site/help/dl/features/ask/"
  Eq 'U3 file: root appends index.html (rendered tree)'        'url.file'      'file:///C:/dl-help/help/dl/features/ask/index.html'
  Eq 'U4 a plain folder root is a file: root'                  'url.folder'    'file:///C:/dl-help/help/dl/features/ask/index.html'
  Eq 'U5 no id -> the all-features page'                       'url.noid'      "$site/help/dl/"
  Eq 'U6 normalise: folder -> file:///C:/dl-help'              'norm.folder'   'file:///C:/dl-help'
  Eq 'U7 normalise: empty -> the default root'                 'norm.empty'    $site
  Eq 'U8 normalise: blanks -> the default root'                'norm.blank'    $site
  Eq 'U9 normalise: trailing slashes stripped'                 'norm.webslash' $site
  Eq 'U10 normalise: backslashes in a file: URL become /'      'norm.filebs'   'file:///C:/dl-help'
  Eq 'U11 normalise: an http root keeps its path prefix'       'norm.prefix'   'http://intranet/docs'
  Eq 'U12 all features, web'                                   'all.web'       "$site/help/dl/"
  Eq 'U13 all features, file'                                  'all.file'      'file:///C:/dl-help/help/dl/index.html'
  Eq 'U14 menu tree, web'                                      'ide.web'       "$site/help/dl/ide/"
  Eq 'U15 menu tree, file'                                     'ide.file'      'file:///C:/dl-help/help/dl/ide/index.html'
  Eq 'U18 file: root -> its local folder'                      'folder.file'   'C:\dl-help'
  Eq 'U19 web root -> no local folder'                         'folder.web'    ''
  Eq 'U20 DL_DEFAULT_HELP_ROOT is the website'                 'default.const' $site
  Write-Host '-- S: HelpRoot setting (test registry root)' -ForegroundColor Cyan
  Eq 'S1 DefaultSettings.HelpRoot = the default root'          'settings.default' $site
  Eq 'S2 a folder is saved normalised and loads back'          'settings.folder'  'file:///C:/dl-help'
  Eq 'S3 empty on disk reads as the default'                   'settings.empty'   $site

  Write-Host '-- I: offline feature list (index-sample.json)' -ForegroundColor Cyan
  Eq 'I1 LoadFromFile succeeds on the fixture'                 'index.load'    'True'
  Eq 'I2 six rows'                                             'index.count'   '6'
  Eq 'I3 Loaded is True'                                       'index.loaded'  'True'
  Eq 'I4 a row with two menus keeps both, in order'            'index.r1.menus' 'drag-lint > Uses & Deps > Circular > Fix...|drag-lint > Refactor > Fix...'
  Eq 'I5 an absent verb reads as empty'                        'index.r1.verb' ''
  Eq 'I6 verb + file read'                                     'index.r0.verb' 'cycles'
  Eq 'I7 file field read'                                      'index.r0.file' 'features/cycles-report.md'
  Eq 'I8 a row without menus has an empty array'               'index.r3.menus' '0'
  Eq 'I9 ... and without context too'                          'index.r3.context' '0'
  Eq 'I10 context paths read'                                  'index.r2.context' 'Code Editor > drag-lint > Recycle Cache'
  Eq 'I11 malformed JSON: LoadFromFile returns False'          'bad.load'      'False'
  Eq 'I12 ... Loaded False'                                    'bad.loaded'    'False'
  Eq 'I13 ... zero rows'                                       'bad.count'     '0'
  Eq 'I14 ... LastError non-empty'                             'bad.error'     'True'
  Eq 'I15 a missing file: False, no exception'                 'missing.load'  'False'
  Eq 'I16 unchanged file: no reload'                           'reload.same'   'False'
  Eq 'I17 changed size/mtime: reloaded'                        'reload.changed' 'True'
  Eq 'I18 ... with the new rows'                               'reload.count'  '1'
  Write-Host '-- L: locator order (spec 3.2)' -ForegroundColor Cyan
  Eq 'L1 engine dir first'                                     'loc.engine'    $kv['loc.engine.want']
  Eq 'L2 then the file: help root'                             'loc.file'      $kv['loc.file.want']
  Eq 'L3 a web root is skipped -> the dev tree'                'loc.webroot'   $kv['loc.dev.want']
  Eq 'L4 no engine dir -> the dev tree'                        'loc.noengine'  $kv['loc.dev.want']
  Eq 'L5 none exists -> empty'                                 'loc.none'      ''
  Check 'L0 the locator expectations were printed'             ([bool]$kv['loc.engine.want'] -and [bool]$kv['loc.dev.want']) ''

  Write-Host '-- M: matcher, display text, caption -> id (spec 3.3 / 3.5)' -ForegroundColor Cyan
  Eq 'M1 empty query -> no hits'                               'match.empty'   '0'
  Eq 'M2 blank query -> no hits'                               'match.blank'   '0'
  Eq 'M3 rank: title prefix < title contains < caption < id/verb; ties by title' 'match.cyc' 'cycles-report:0|uses-cycle-fix:1|structure-tree:2|call-graph-cyc:3|db-compact:3'
  Eq 'M4 case-insensitive and trimmed'                         'match.CYC'     'cycles-report:0|uses-cycle-fix:1|structure-tree:2|call-graph-cyc:3|db-compact:3'
  Eq 'M5 the summary is never searched'                        'match.summary' ''
  Eq 'M6 a title-only row matches on its title'                'match.title'   'about-box:0'
  Eq 'M7 at most 12 hits'                                      'match.cap'     '12'
  Eq 'M8 display: title - menu path'                           'display.menu'  'Cycles Report - drag-lint > Reports > Circular Uses Report...'
  Eq 'M9 display: several menus -> the shortest'               'display.shortest' 'Uses Cycle Fix - drag-lint > Refactor > Fix...'
  Eq 'M10 display: no menu -> the context path'                'display.context' 'Structure Tree - Code Editor > drag-lint > Recycle Cache'
  Eq 'M11 display: neither -> the title'                       'display.title' 'About drag-lint'
  Eq 'M12 display: verb only -> CLI: drag-lint <verb>'         'display.cli'   'Database Compaction - CLI: drag-lint recycle'
  Eq 'M13 a hit carries its display text'                      'match.cyc.display0' 'Cycles Report - drag-lint > Reports > Circular Uses Report...'
  Eq 'M14 caption -> the id whose menu path ends with it'      'caption.fix'   'uses-cycle-fix'
  Eq 'M15 accelerator & ignored'                               'caption.amp'   'uses-cycle-fix'
  Eq 'M16 caption of a single-menu row'                        'caption.graph' 'call-graph-cyc'
  Eq 'M17 a context path counts too'                           'caption.context' 'structure-tree'
  Eq 'M18 unknown caption -> empty'                            'caption.none'  ''
  Eq 'M19 an inner segment is not a caption'                   'caption.inner' ''

  Eq 'M20 resolve: an id in the loaded list -> its page'       'resolve.known'   "$site/help/dl/features/call-graph-cyc/"
  Eq 'M21 resolve: an id NOT in the loaded list -> all features' 'resolve.unknown' "$site/help/dl/"
  Eq 'M22 resolve: no list loaded -> the page, unchecked'      'resolve.nolist'  "$site/help/dl/features/no-such-id/"
  Eq 'M23 resolve: nil list -> the page, unchecked'            'resolve.nil'     "$site/help/dl/features/no-such-id/"

  Write-Host '-- W: wiring (source pins; the UI itself needs a live IDE)' -ForegroundColor Cyan
  $ed = [IO.File]::ReadAllText((Join-Path $pluginDir 'DragLint.Plugin.Editor.pas'))
  $df = [IO.File]::ReadAllText((Join-Path $pluginDir 'DragLint.Plugin.DockForm.pas'))
  $dpk = [IO.File]::ReadAllText((Join-Path $pluginDir 'dclDragLintWizard.dpk'))
  $dproj = [IO.File]::ReadAllText((Join-Path $pluginDir 'dclDragLintWizard.dproj'))
  Check 'W1 the GitHub-wiki constant is gone (spec 3.1)' (-not $ed.Contains('DL_WIKI_BASE_URL')) ''
  Check 'W2 both existing Help items open their registry ids' `
    ($ed.Contains("DLOpenHelp('ide-menu-reference')") -and $ed.Contains("DLOpenHelp('effect-summary-legend')")) ''
  Check 'W3 Help > "Help on a feature..." and "All features (web)" exist' `
    ($ed.Contains("AddWrappedItem(SubHelp, 'Help on a feature...', InvokeHelpOnFeature)") -and $ed.Contains("AddWrappedItem(SubHelp, 'All features (web)', InvokeHelpAllFeatures)")) ''
  Check 'W4 the registry-surfaced captions are unchanged (no menu-path drift)' `
    ($ed.Contains("'IDE Menu Reference (wiki)'") -and $ed.Contains("'Effect Summary Legend (wiki)'")) ''
  $ctor = [regex]::Match($df, 'constructor TDragLintDockFrame\.Create[\s\S]*?end; // constructor').Value
  $iSb = $ctor.IndexOf('TDragLintStatusBar.Create'); $iHl = $ctor.IndexOf('TDLHelpLine.Create'); $iPg = $ctor.IndexOf('TPageControl.Create')
  Check 'W5 the help line is created after the status strip, before the pages' (($iSb -ge 0) -and ($iHl -gt $iSb) -and ($iPg -gt $iHl)) "sb=$iSb hl=$iHl pages=$iPg"
  $units = 'DragLint.Plugin.HelpIndex','DragLint.Plugin.Help','DragLint.Plugin.HelpLine','DragLint.Plugin.QueueText'
  $missing = @($units | Where-Object { -not $dpk.Contains("$_ in '$_.pas'") -or -not $dproj.Contains("<DCCReference Include=`"$_.pas`"/>") })
  Check 'W6 the four new units are in the .dpk contains and the .dproj (HOWTO rule 4)' ($missing.Count -eq 0) "missing: $($missing -join ', ')"

  $of = [IO.File]::ReadAllText((Join-Path $pluginDir 'DragLint.Plugin.OptionsFrames.pas'))
  Check 'W7 Options > General: HelpRoot loads and saves through DLNormaliseHelpRoot' `
    ($of.Contains('FEdHelpRoot         .Text   := DLNormaliseHelpRoot(FSettings.HelpRoot);') -and $of.Contains('ASettings.HelpRoot             := DLNormaliseHelpRoot(FEdHelpRoot.Text);')) ''
  Check 'W8 the Test button opens the all-features page of the root as typed' `
    ($of.Contains('DLOpenHelpUrl(DLHelpAllUrl(DLNormaliseHelpRoot(FEdHelpRoot.Text)));')) ''

  Write-Host '-- Q: queue task lines (spec 3.6)' -ForegroundColor Cyan
  Eq 'Q1 depth 0 -> no lines (the strip stays as today)'       'queue.d0'      '0'
  Eq 'Q2 depth 1 -> Now (pct + phase) + Next'                  'queue.d1'      'Now: Index project - 45%  uMain.pas|Next: Lint all'
  Eq 'Q3 depth 3 -> Now + Next + Then + Then'                  'queue.d3'      'Now: Index project - 45%|Next: Lint all|Then: Forms CSV|Then: Reindex lib'
  Eq 'Q4 depth 5 -> ... + "+ 2 more waiting"'                  'queue.d5'      'Now: Index project - 45%|Next: Lint all|Then: Forms CSV|Then: Reindex lib|+ 2 more waiting'
  Eq 'Q5 percent -1 -> "Now: <title> ..."'                     'queue.indet'   'Now: Index project ...|Next: Lint all'
  Eq 'Q6 nothing running yet -> no Now line'                   'queue.idle'    'Next: Lint all'
  $jq = [IO.File]::ReadAllText((Join-Path $pluginDir 'DragLint.Plugin.JobQueue.pas'))
  $depthWrites = [regex]::Matches($jq, 'FState\.QueueDepth\s*:=').Count
  Check 'Q7 every QueueDepth write is the one in SyncPendingLocked (paired with PendingTitles)' `
    (($depthWrites -eq 1) -and ($jq -match 'SetLength\(FState\.PendingTitles') -and ($jq -match 'FState\.PendingTitles\[I\]\s*:=')) "QueueDepth writes: $depthWrites"
  $sb = [IO.File]::ReadAllText((Join-Path $pluginDir 'DragLint.Plugin.StatusBar.pas'))
  Check 'Q8 StatesEqual compares PendingTitles' ([regex]::Match($sb, 'function TDragLintStatusBar\.StatesEqual[\s\S]*?end;').Value -match 'PendingTitles') ''
}
catch {
  Check "runner: $($_.Exception.Message)" $false
}
finally {
  Set-Location -LiteralPath $env:TEMP
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
Write-Host ''
if ($script:Failed) { Write-Host 'HELP LINE: FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'HELP LINE: PASS' -ForegroundColor Green; exit 0 }
