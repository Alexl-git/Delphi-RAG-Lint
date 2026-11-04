<#
  run_target_bds_libpath_guard.ps1 -- GH #13 (Jonathas Paiva's report): the index
  of a project that targets an older Delphi takes the library path, the platform
  list, the IDE Environment Variables and $(BDS) from THAT Studio's BDS key.

  Runs on a machine with one Studio: DRAGLINT_TEST_BDS_REGISTRY names a JSON file
  that replaces the whole HKCU/HKLM BDS tree for this process. The real registry
  is never written, and no real project or library DB is touched: every run passes
  --db into this guard's own temp folder, with --library-db naming an absent file.

  What a second real Studio would prove and this cannot: see the wiki page
  docs\wiki\target-bds-library-path.md, "Not tested here".
#>
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$Scratch = ''
)
$ErrorActionPreference = 'Continue'
$Exe = (Resolve-Path $Exe).Path
if ($Scratch -eq '') { $Scratch = Join-Path ([IO.Path]::GetTempPath()) ("dl-gh13-" + [Guid]::NewGuid().ToString('N')) }
[void][IO.Directory]::CreateDirectory($Scratch)
$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name" }
  else { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}
function WriteText([string]$Path, [string]$Text) {
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}
function WriteUnit([string]$Path, [string]$Name, [string]$UsesList, [string]$Decl, [string]$Body) {
  $u = if ($UsesList) { "uses $UsesList;`n" } else { '' }
  WriteText $Path "unit $Name;`ninterface`n$Decl`nimplementation`n$u$Body`nend.`n"
}
function WriteRegistry([string]$Path, $Tree) {
  [IO.File]::WriteAllText($Path, ($Tree | ConvertTo-Json -Depth 8), [Text.Encoding]::ASCII)
}
function Dl([string[]]$DlArgs, [string]$Registry) {
  $env:DRAGLINT_TEST_BDS_REGISTRY = $Registry
  $out = & $Exe @DlArgs 2>&1 | Out-String
  $env:DRAGLINT_TEST_BDS_REGISTRY = ''
  return $out
}
function Studio([string]$Root, [string]$Search, $EnvVars = @{}) {
  return @{ RootDir = $Root; Library = @{ Win32 = @{ 'Search Path' = $Search; 'Browsing Path' = '' }; Win64 = @{ 'Search Path' = $Search; 'Browsing Path' = '' } }; 'Environment Variables' = $EnvVars }
}
function DprojText([string]$ProjectVersion, [string]$Name) {
  $pv = if ($ProjectVersion) { "<ProjectVersion>$ProjectVersion</ProjectVersion>" } else { '' }
  return "<Project><PropertyGroup>$pv<MainSource>$Name.dpr</MainSource></PropertyGroup><ItemGroup><DCCReference Include=`"uCaller.pas`"/></ItemGroup></Project>`n"
}
function WriteProject([string]$Dir, [string]$ProjectVersion) {
  WriteText "$Dir\P.dproj" (DprojText $ProjectVersion 'P')
  WriteText "$Dir\P.dpr" "program P;`nuses uCaller in 'uCaller.pas';`nbegin`nend.`n"
  WriteUnit "$Dir\uCaller.pas" 'uCaller' 'uLibOnly, uStudioOwned, uCommon' 'procedure CallIt;' "procedure CallIt;`nbegin`n  LibProc;`nend;"
}
function ClosureOf([string]$Project, [string]$Registry, [string[]]$More = @()) {
  $o = Dl (@('selftest', 'closure', '--project', $Project) + $More) $Registry
  return @($o -split "`r?`n" | Where-Object { $_ -match '\.pas$' })
}
function Named($Files, [string]$Leaf) { return @($Files | Where-Object { [IO.Path]::GetFileName($_) -ieq $Leaf }).Count -gt 0 }

# --- the machine: three Studios that exist only in JSON --------------------
$s20 = Join-Path $Scratch 'Studio\20.0'
$s23 = Join-Path $Scratch 'Studio\23.0'
$s37 = Join-Path $Scratch 'Studio\37.0'
$team20 = Join-Path $Scratch 'D\Team20'
$team23 = Join-Path $Scratch 'D\Team23'
$common = Join-Path $Scratch 'D\Common'
WriteUnit "$s20\source\rtl\uStudioOwned.pas" 'uStudioOwned' '' '' ''
WriteUnit "$s23\source\rtl\uStudioOwned.pas" 'uStudioOwned' '' '' ''
[void][IO.Directory]::CreateDirectory($s37)
WriteUnit "$team20\uLibOnly.pas" 'uLibOnly' 'uLibDeep' 'procedure LibProc;' "procedure LibProc;`nbegin`n  DeepProc;`nend;"
WriteUnit "$team20\uLibDeep.pas" 'uLibDeep' '' 'procedure DeepProc;' "procedure DeepProc;`nbegin`nend;"
WriteUnit "$team23\uLibOnly.pas" 'uLibOnly' '' 'procedure LibProc;' "procedure LibProc;`nbegin`nend;"
WriteUnit "$common\uCommon.pas" 'uCommon' '' '' ''

$search20 = "`$(BDS)\source\rtl;`$(TEAMLIB);$common"
$search23 = "`$(BDS)\source\rtl;$team23;$common"
$reg = Join-Path $Scratch 'registry.json'
WriteRegistry $reg @{ '20.0' = (Studio $s20 $search20 @{ TEAMLIB = $team20 }); '23.0' = (Studio $s23 $search23); '37.0' = (Studio $s37 $common) }
$regNo20 = Join-Path $Scratch 'registry-no20.json'
WriteRegistry $regNo20 @{ '37.0' = (Studio $s37 $common) }
$regPathless = Join-Path $Scratch 'registry-pathless.json'
WriteRegistry $regPathless @{ '20.0' = (Studio $s20 "`$(BDS)\source\rtl;$common" @{ TEAMLIB = $team20 }); '37.0' = (Studio $s37 $common) }

$p103 = Join-Path $Scratch 'P103'; WriteProject $p103 '18.8'
$p13 = Join-Path $Scratch 'P13'; WriteProject $p13 '20.5'
$pNone = Join-Path $Scratch 'PNone'; WriteProject $pNone ''
$pOld = Join-Path $Scratch 'POld'; WriteProject $pOld '14.4'
$noLib = Join-Path $Scratch 'no-library.sqlite'

Write-Host '[1] the issue repro: a 10.3 project, a library-only unit'
$db = Join-Path $Scratch 'p103.sqlite'
$idx = Dl @('index', '--project', "$p103\P.dproj", '--platform', 'win32', '--db', $db, '--library-db', $noLib) $reg
$callers = Dl @('query', 'find-callers', '--name', 'LibProc', '--resolved', '--db', $db) $reg
$dump = Dl @('selftest', 'files', '--db', $db) $reg
Check 'uLibOnly.pas is indexed' ($dump -match [regex]::Escape("$team20\uLibOnly.pas")) $dump
Check 'its own use uLibDeep.pas is indexed too (the walk continues through the tail)' ($dump -match 'uLibDeep\.pas') $dump
Check 'find-callers --resolved lists the caller' ($callers -match 'CallIt') $callers
Check '$(BDS) expanded to 20.0''s root: its own source stays out' (-not ($dump -match 'uStudioOwned\.pas')) $dump
Check 'a folder Delphi 13''s library DB covers stays out' (-not ($dump -match 'uCommon\.pas')) $dump
Check 'no fallback note when the key is installed' (-not ($idx -match 'not installed')) $idx
Check 'the run says which Studio it read' ($idx -match 'Library path: BDS 20\.0') $idx

Write-Host '[2] key missing: fall back to 37.0, one line naming both'
$db2 = Join-Path $Scratch 'fallback.sqlite'
$idx2 = Dl @('index', '--project', "$p103\P.dproj", '--platform', 'win32', '--db', $db2, '--library-db', $noLib, '--json') $regNo20
$noteLines = @($idx2 -split "`r?`n" | Where-Object { $_ -match '^(drag-lint: )?note: library path' })
Check 'exactly one note line' ($noteLines.Count -eq 1) $idx2
Check 'the note names requested and used' (($noteLines -join '') -match 'BDS 20\.0.*not installed.*BDS 37\.0') $idx2
$jsonLine = @($idx2 -split "`r?`n" | Where-Object { $_ -match '^\{.*"library_path"' }) | Select-Object -Last 1
Check '--json summary carries the same facts' (($jsonLine -match '"requested_bds":"20\.0"') -and ($jsonLine -match '"used_bds":"37\.0"') -and ($jsonLine -match '"note":"')) $jsonLine
$cf = ClosureOf "$p103\P.dproj" $regNo20
Check 'the fallback closure has no library-only unit (as today)' (-not (Named $cf 'uLibOnly.pas')) ($cf -join ';')

Write-Host '[3] --target-compiler wins over ProjectVersion'
$c12 = ClosureOf "$p103\P.dproj" $reg @('--target-compiler', '12', '--platform', 'win32')
Check 'Delphi 12: 23.0''s copy of uLibOnly' (Named ($c12 | Where-Object { $_ -like "$team23*" }) 'uLibOnly.pas') ($c12 -join ';')
Check 'and not 20.0''s' (-not (Named ($c12 | Where-Object { $_ -like "$team20*" }) 'uLibOnly.pas')) ($c12 -join ';')
$c13 = ClosureOf "$p103\P.dproj" $reg @('--target-compiler', '13')
Check '--target-compiler 13 on a 10.3 project: the Delphi 13 closure' (-not (Named $c13 'uLibOnly.pas')) ($c13 -join ';')

Write-Host '[4] positive control: a Delphi 13 project has exactly the closure it has without a target'
$cA = (ClosureOf "$p13\P.dproj" $reg | ForEach-Object { $_.Replace($p13, '<P>') }) -join "`n"
$cB = (ClosureOf "$pNone\P.dproj" $reg | ForEach-Object { $_.Replace($pNone, '<P>') }) -join "`n"
Check 'ProjectVersion 20.5 = no ProjectVersion, byte for byte' ($cA -ceq $cB) "[$cA] vs [$cB]"
Check 'and it holds the project''s own unit (the comparison is not of two empties)' ($cA -match 'uCaller\.pas') $cA
Check 'and no library-only unit' (-not ($cA -match 'uLibOnly\.pas')) $cA

Write-Host '[5] no noise: no target, or an older ProjectVersion the table does not map'
foreach ($case in @(@('no ProjectVersion', $pNone), @('ProjectVersion 14.4', $pOld))) {
  $dbQ = Join-Path $Scratch ("quiet-" + [Guid]::NewGuid().ToString('N') + '.sqlite')
  $q = Dl @('index', '--project', "$($case[1])\P.dproj", '--platform', 'win32', '--db', $dbQ, '--library-db', $noLib) $regNo20
  Check "$($case[0]): no library-path note" (-not ($q -match '(?i)library path')) $q
  Check "$($case[0]): the index still ran" ($q -match 'Done\. Files:') $q
}

Write-Host '[6] the verbs that compute a closure agree: a library unit is not a project gap'
$rec = Dl @('reconcile-project', "$p103\P.dproj", '--json') $reg
Check 'reconcile-project does not report uLibOnly MISSING' (-not ($rec -match 'uLibOnly')) $rec
Check 'reconcile-project --json names the Studio it read' ($rec -match '"used_bds"\s*:\s*"20\.0"') $rec
$recNo = Dl @('reconcile-project', "$p103\P.dproj", '--json') $regNo20
Check 'reconcile-project --json carries the fallback note' (($recNo -match '"requested_bds"\s*:\s*"20\.0"') -and ($recNo -match '"used_bds"\s*:\s*"37\.0"')) $recNo
$lintDpr = Dl @('lint', '--project', "$p103\P.dproj", '--rule', 'unit-not-in-dpr', '--db', $db) $reg
Check 'unit-not-in-dpr does not flag the library-only unit' (-not ($lintDpr -match 'uLibOnly|uLibDeep')) $lintDpr
$dry = Dl @('index', '--project', "$p103\P.dproj", '--platform', 'win32', '--db', (Join-Path $Scratch 'dry.sqlite'), '--library-db', $noLib, '--dry-run') $reg
Check 'a dry run lists the same closure' ($dry -match 'uLibOnly\.pas') $dry

Write-Host '[7] incremental: a path change alone reaches the next index --project'
$dbI = Join-Path $Scratch 'incremental.sqlite'
[void](Dl @('index', '--project', "$p103\P.dproj", '--platform', 'win32', '--db', $dbI, '--library-db', $noLib) $regPathless)
$before = Dl @('selftest', 'files', '--db', $dbI) $regPathless
Check 'before: not indexed' (-not ($before -match 'uLibOnly\.pas')) $before
[void](Dl @('index', '--project', "$p103\P.dproj", '--platform', 'win32', '--db', $dbI, '--library-db', $noLib) $reg)
$after = Dl @('selftest', 'files', '--db', $dbI) $reg
$cAfter = Dl @('query', 'find-callers', '--name', 'LibProc', '--resolved', '--db', $dbI) $reg
Check 'after the path change, no source touched: indexed' ($after -match 'uLibOnly\.pas') $after
Check 'and the caller that was already stored now resolves' ($cAfter -match 'CallIt') $cAfter
$idxLeft = Dl @('index', '--project', "$p103\P.dproj", '--platform', 'win32', '--db', $dbI, '--library-db', $noLib) $regPathless
$left = Dl @('selftest', 'files', '--db', $dbI) $regPathless
Check 'a folder leaving the path keeps its rows until --rebuild (the documented files > walked state)' ($left -match 'uLibOnly\.pas') $left
[void](Dl @('index', '--project', "$p103\P.dproj", '--platform', 'win32', '--db', $dbI, '--library-db', $noLib, '--rebuild') $regPathless)
$gone = Dl @('selftest', 'files', '--db', $dbI) $regPathless
Check '--rebuild removes them' (-not ($gone -match 'uLibOnly\.pas')) $gone

Write-Host '[8] index --all and --jobs read the same key, section by section'
$cfg = Join-Path $Scratch 'all.json'
$secs = @(@{ name = 'P103'; include = @("$p103\P.dproj") }, @{ name = 'P13'; include = @("$p13\P.dproj") })
[IO.File]::WriteAllText($cfg, (@{ settings = @{ defaultPlatform = 'Win32'; maxJobs = 2 }; indexes = @{ sections = $secs } } | ConvertTo-Json -Depth 8), [Text.Encoding]::ASCII)
$planText = Dl @('index', '--all', '--config', $cfg, '--dry-run', '--json') $reg
$plan = ($planText.Substring($planText.IndexOf('{'))) | ConvertFrom-Json
$sec103 = @($plan.sections | Where-Object { $_.name -like 'P103*' })[0]
$sec13 = @($plan.sections | Where-Object { $_.name -like 'P13*' })[0]
Check 'the dry-run JSON names 20.0 for the 10.3 section' ($sec103.used_bds -eq '20.0') $planText
Check 'and 37.0 for the Delphi 13 section' ($sec13.used_bds -eq '37.0') $planText
$planNo = Dl @('index', '--all', '--config', $cfg, '--dry-run', '--json') $regNo20
Check 'the dry-run JSON carries the fallback note' ($planNo -match 'not installed') $planNo
$all = Dl @('index', '--all', '--config', $cfg, '--jobs', '2') $reg
Check '--all --jobs prints the section''s Studio' ($all -match 'Library path: BDS 20\.0') $all
$f103 = Dl @('selftest', 'files', '--db', $sec103.db) $reg
$f13 = Dl @('selftest', 'files', '--db', $sec13.db) $reg
Check '--jobs: the 10.3 section indexed the library-only unit' ($f103 -match 'uLibOnly\.pas') $f103
Check '--jobs: the Delphi 13 section did not' (-not ($f13 -match 'uLibOnly\.pas')) $f13

Write-Host ''
Write-Host "target-bds-libpath: pass=$script:pass fail=$script:fail"
if ($script:fail -gt 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS'
exit 0
