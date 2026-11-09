# run_cyclefix_hubsurface_dcc.ps1 -- lane 148 HP2 (spec 2026-11-08-hub-scc-phased P2): recipe R3
# `cycles --plan --hub-surface` on a hub-shaped circular group (fixture tests\fixtures\cyclefix\hubsurface:
# HubMain owns the global HubMainForm, three spokes read it, HubMain calls them back). Real dcc proves --apply.
#
#   h0  control: --plan WITHOUT --hub-surface prints no R3 block (the default is unchanged)
#   h1  plan: exit 0; IHubMainHub in HubMain.Hub; 4 members (1 read-only, 1 read/write, 2 methods);
#       3 spokes rewritten, 3 edges cut, the group breaks; dry run writes nothing   (RED on 1.46.0: unknown flag)
#   h2  --apply: exit 0; HubMain.Hub.pas written; builds; stdout byte-identical; comment + string literal untouched
#   h3  no cycle after a re-index
#   n1  a bare use (Assigned(HubMainForm)) refuses that spoke: bare-use; the group stays
#   n2  a write to a designer field refuses member-write
#   n3  Inc on a Char plain field refuses member-write (var parameter); Inc / Dec on an Integer one is rewritten (h2.8)
#   p1  a spoke that also calls a hub routine: R1 inverts it (HubStampPtr in HubMain.Hub), the edge is cut (phase P3, 149 CYA)
#   p2  --apply with that routine builds, stdout identical, no cycle after a re-index
#   p3  control: a call from the spoke's initialization keeps the edge (init-order)
#   p4  control: a routine whose signature names a type of the cycle is refused (signature-in-cycle)
#   n5  an ancestor's member (Tag) WITHOUT a library is refused member-unsupported, and only its spoke
#   p5  with the platform library: TComponent.Tag (rw property) and HasParent (method) are on the surface (149 CYA)
#   p6  --apply with them builds, stdout identical
#   n6  a two-unit knot has two hubs: not-hub-shaped, exit 1; --apply on it writes nothing
#   q1  P6 prep: --plan --hub-surface = the playbook with R3 (and the P1 hub block) in place of Part A for the hub group
#   q2  control: a group R3 refuses gets a note and the planner's plan
#   q3  --causes --format json --hub-surface: R3's fix object, no planner; q4 control: default fix object unchanged; q5 bad combo exit 2
#
# Usage: pwsh -File run_cyclefix_hubsurface_dcc.ps1 [-Exe <drag-lint.exe>] [-WorkDir <dir>] [-KeepWorkDir]
param(
  [string]$Exe     = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe") { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" } else { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }),
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-hubsurface-$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $RsVars)) { Write-Host "SKIP: no rsvars.bat ($RsVars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Ascii = [Text.Encoding]::ASCII
$script:N = 0

function Edit-Text([string]$Path, [string]$From, [string]$To) {
  $t = [IO.File]::ReadAllText($Path, $Ascii)
  $f = $From -replace "`r?`n", "`r`n"
  if (-not $t.Contains($f)) { throw "patch anchor not found in ${Path}: $From" }
  [IO.File]::WriteAllText($Path, $t.Replace($f, ($To -replace "`r?`n", "`r`n")), $Ascii)
}
function Get-SrcHash([string]$Dir) {
  return ((Get-ChildItem $Dir -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } | Sort-Object Name |
    ForEach-Object { '{0}={1}' -f $_.Name, (Get-FileHash $_.FullName -Algorithm SHA256).Hash }) -join ';')
}
function New-Proj([string]$Fix, [string]$Name, [scriptblock]$Patch = $null) {
  $script:N++
  $root = Join-Path $WorkDir ("p{0}" -f $script:N)
  New-Item -ItemType Directory -Force $root | Out-Null
  $from = Join-Path $Repo "tests\fixtures\cyclefix\$Fix"
  Get-ChildItem $from -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } | ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) }
  if ($Patch) { & $Patch $root }
  $db = "$root.sqlite"
  Push-Location $WorkDir
  try { $null | & $Exe index --project (Join-Path $root "$Name.dproj") --db $db --library-db none *> "$db.log" } finally { Pop-Location }
  return @{ Root = $root; Dproj = (Join-Path $root "$Name.dproj"); Db = $db; Name = $Name }
}
function Get-HubPlan($P, [string[]]$Extra = @(), [string]$Lib = 'none') {
  $a = @('cycles', '--plan', '--hub-surface', '--db', $P.Db, '--library-db', $Lib) + $Extra
  Push-Location $WorkDir
  try { $out = ($null | & $Exe @a 2>&1 | Out-String); $code = $LASTEXITCODE } finally { Pop-Location }
  return @{ Exit = $code; Out = $out }
}
function Get-Cycles($P) {
  Push-Location $WorkDir
  try {
    $null | & $Exe index --project $P.Dproj --db $P.Db --library-db none *> "$($P.Db).relog"
    return ($null | & $Exe cycles --db $P.Db --library-db none 2>$null | Out-String)
  } finally { Pop-Location }
}
function Invoke-Build($P) {
  $bat = "$($P.Root).build.bat"; $log = "$bat.log"
  $lines = @('@echo off', ('call "{0}"' -f $RsVars), ('cd /d "{0}"' -f $P.Root),
    ('msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal "{0}" > "{1}" 2>&1' -f $P.Dproj, $log),
    ('>> "{0}" echo BUILD_EXITCODE=%ERRORLEVEL%' -f $log))
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), $Ascii)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -NoNewWindow -Wait | Out-Null
  $text = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '' }
  $errors = @([regex]::Matches($text, '(?m)^.*\b(error|fatal) [EF]\d{4}\b.*$') | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
  return @{ Ok = ($text -match 'BUILD_EXITCODE=0') -and ($errors.Count -eq 0); Errors = ($errors -join ' | ') }
}
function Invoke-Program($P) {
  $exeP = Join-Path $P.Root "Win64\Debug\$($P.Name).exe"
  if (-not (Test-Path $exeP)) { return '<no exe>' }
  $o = "$exeP.stdout"
  Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait -RedirectStandardOutput $o -RedirectStandardError "$exeP.stderr" | Out-Null
  return [IO.File]::ReadAllText($o, $Ascii)
}
function Has([string]$Text, [string]$Literal) { return $Text.Contains($Literal) }

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  Write-Host '== h: the hub-surface plan and its apply' -ForegroundColor Cyan
  $P0 = New-Proj 'hubsurface' 'HubSurface'
  Push-Location $WorkDir
  try { $def = ($null | & $Exe cycles --plan --db $P0.Db --library-db none 2>&1 | Out-String) } finally { Pop-Location }
  Check 'h0 control: --plan without --hub-surface prints no R3 block' (($def -notmatch 'hub-surface recipe R3') -and ($def -match '(?i)group|cycle')) $def
  $h0 = Get-SrcHash $P0.Root
  $r = Get-HubPlan $P0
  $o = $r.Out
  Check 'h1.1 exit 0' ($r.Exit -eq 0) "exit=$($r.Exit) $o"
  Check 'h1.2 the R3 block names the surface' (Has $o '## Group 1 (4 units): hub-surface recipe R3') $o
  Check 'h1.3 IHubMainHub in the new unit HubMain.Hub, global HubMainHub' (Has $o '`THubMain` -> interface `IHubMainHub` in the new unit `HubMain.Hub` (HubMain.Hub.pas), global `HubMainHub`') $o
  Check 'h1.4 4 members: Log read-only, Counter read/write, Note + Ready methods' (Has $o '- surface: 4 of 4 members -- 1 read-only (designer fields), 1 read/write (plain fields), 2 methods') $o
  Check 'h1.5 3 spokes rewritten, 0 refused' ($o -match '- spokes: 3 rewritten \(\d+ receivers `HubMainForm\.` -> `HubMainHub\.`\), 0 refused') $o
  Check 'h1.6 3 edges cut' (Has $o '- uses: 3 spokes drop `HubMain` (edge cut); 0 keep it') $o
  Check 'h1.7 prediction: the group breaks' (Has $o '- prediction: the group breaks') $o
  Check 'h1.8 the interface text: property Log read-only, Counter read/write, Note with its default' ((Has $o 'property Log: TStringList read HubGetLog;') -and (Has $o 'property Counter: Integer read HubGetCounter write HubSetCounter;') -and (Has $o 'procedure Note(const pText: string; pLevel: Integer = 0);') -and (Has $o 'function Ready: Boolean;')) $o
  Check 'h1.9 dry run: nothing written' ((Has $o 'dry run: nothing written') -and ((Get-SrcHash $P0.Root) -eq $h0) -and -not (Test-Path (Join-Path $P0.Root 'HubMain.Hub.pas'))) $o

  $B = New-Proj 'hubsurface' 'HubSurface'
  $b0 = Invoke-Build $B
  Check 'h2.0 untouched copy builds' $b0.Ok $b0.Errors
  $out0 = Invoke-Program $B
  $P = New-Proj 'hubsurface' 'HubSurface'
  $a = Get-HubPlan $P @('--apply')
  Check 'h2.1 --apply: exit 0, written' (($a.Exit -eq 0) -and (Has $a.Out 'written: 4 files + new `HubMain.Hub.pas`')) "exit=$($a.Exit) $($a.Out)"
  $b1 = Invoke-Build $P
  Check 'h2.2 the applied copy builds (independent msbuild)' $b1.Ok $b1.Errors
  $out1 = Invoke-Program $P
  Check 'h2.3 stdout is byte-identical to the untouched build' (($out0 -ne '<no exe>') -and ($out1 -ceq $out0) -and ($out0 -match 'C True')) "before=[$out0] after=[$out1]"
  $sb = [IO.File]::ReadAllText((Join-Path $P.Root 'HubSpokeB.pas'), $Ascii)
  Check 'h2.4 HubSpokeB: receivers rewritten, comment and string literal untouched, uses HubMain.Hub only' ((Has $sb "HubMainHub.Note('B says HubMainForm.Log', 1);") -and (Has $sb '// HubMainForm.Note in a comment stays') -and ($sb -match '(?m)^\s+HubMain\.Hub;') -and ($sb -notmatch '(?m)^\s+HubMain;')) $sb
  $sc = [IO.File]::ReadAllText((Join-Path $P.Root 'HubSpokeC.pas'), $Ascii)
  Check 'h2.5 HubSpokeC: a lower-case receiver is rewritten too' ((Has $sc "HubMainHub.log.Add('C ' + BoolToStr(HubMainHub.Ready, True));")) $sc
  $sa = [IO.File]::ReadAllText((Join-Path $P.Root 'HubSpokeA.pas'), $Ascii)
  Check 'h2.8 HubSpokeA: Inc / Dec on an Integer field become assignments through the surface' ((Has $sa 'HubMainHub.Counter:= HubMainHub.Counter + (2);') -and (Has $sa 'HubMainHub.Counter:= HubMainHub.Counter - 1;') -and ($sa -notmatch 'Inc\(|Dec\(')) $sa
  $hm = [IO.File]::ReadAllText((Join-Path $P.Root 'HubMain.pas'), $Ascii)
  Check 'h2.6 HubMain: heritage, interface uses, hand-over' ((Has $hm 'class(TComponent, IHubMainHub)') -and (Has $hm 'System.Classes, System.SysUtils, HubMain.Hub;') -and (Has $hm 'HubMainHub:= Self;') -and (Has $hm 'HubMainHub:= nil;')) $hm
  Check 'h2.7 backups written' ((Test-Path (Join-Path $P.Root 'HubMain.pas.BCK1')) -and (Test-Path (Join-Path $P.Root 'HubSpokeA.pas.BCK1')))
  $left = Get-Cycles $P
  Check 'h3 no cycle after a re-index' ($left -match 'No circular unit dependencies found\.') $left

  Write-Host '== n: what is refused, and only where it is' -ForegroundColor Cyan
  $E = New-Proj 'hubsurface' 'HubSurface' { param($r) Edit-Text (Join-Path $r 'HubSpokeC.pas') "  hubMainForm.log.Add(" "  if Assigned(HubMainForm) then`n  hubMainForm.log.Add(" }
  $o = (Get-HubPlan $E).Out
  Check 'n1 a bare use refuses that spoke (bare-use), 2 others rewritten, the group stays' ((Has $o '- refused `HubSpokeC.pas`: bare-use') -and ($o -match 'spokes: 2 rewritten') -and (Has $o 'the group stays -- 1 spoke->hub edges remain')) $o
  $E = New-Proj 'hubsurface' 'HubSurface' { param($r) Edit-Text (Join-Path $r 'HubSpokeB.pas') "  if HubMainForm.Ready" "  HubMainForm.Log:= HubMainForm.Log;`n  if HubMainForm.Ready" }
  $o = (Get-HubPlan $E).Out
  Check 'n2 a write to a designer field: member-write' ($o -match '- refused `HubSpokeB\.pas`: member-write -- line \d+: `HubMainForm\.Log :=` writes a component field') $o
  $E = New-Proj 'hubsurface' 'HubSurface' { param($r) Edit-Text (Join-Path $r 'HubSpokeA.pas') "  HubMainForm.Counter:= HubMainForm.Counter + 1;" "  Inc(HubMainForm.Mark);
  HubMainForm.Counter:= HubMainForm.Counter + 1;" }
  $o = (Get-HubPlan $E).Out
  Check 'n3 Inc(HubMainForm.Mark) on a Char: member-write, var parameter' ((Has $o '- refused `HubSpokeA.pas`: member-write') -and (Has $o 'is a var parameter')) $o
  Write-Host '== p: hub free routines through R1 pointers in the surface unit (phase P3, lane 149 CYA)' -ForegroundColor Cyan
  $StampC = { param($r) Edit-Text (Join-Path $r 'HubSpokeC.pas') "  hubMainForm.log.Add(" "  HubStamp('c');`n  hubMainForm.log.Add(" }
  $E = New-Proj 'hubsurface' 'HubSurface' $StampC
  $o = (Get-HubPlan $E).Out
  Check 'p1 a spoke calling a hub routine: HubStamp inverted (R1), 3 cut, the group breaks   (RED on 1.48.0: kept by HubStamp)' ((Has $o '- hub routines (R1, phase P3): 1 of 1 inverted through pointers in `HubMain.Hub`: `HubStamp` -> `HubStampPtr` (1 spokes)') -and (Has $o '- uses: 3 spokes drop `HubMain` (edge cut); 0 keep it') -and (Has $o '- prediction: the group breaks') -and (Has $o 'THubStampPtr = procedure(const pTag: string);') -and (Has $o 'HubStampPtr: THubStampPtr;')) $o
  $B = New-Proj 'hubsurface' 'HubSurface' $StampC
  $b0 = Invoke-Build $B
  $out0 = Invoke-Program $B
  $P = New-Proj 'hubsurface' 'HubSurface' $StampC
  $a = Get-HubPlan $P @('--apply')
  $b1 = Invoke-Build $P
  $out1 = Invoke-Program $P
  Check 'p2.1 --apply with the routine: exit 0, untouched + applied copies build' (($a.Exit -eq 0) -and $b0.Ok -and $b1.Ok) "exit=$($a.Exit) base=[$($b0.Errors)] applied=[$($b1.Errors)] $($a.Out)"
  Check 'p2.2 stdout byte-identical, the stamp still printed through the pointer' (($out0 -ne '<no exe>') -and ($out1 -ceq $out0) -and ($out0 -match 'stamp c')) "before=[$out0] after=[$out1]"
  $sc = [IO.File]::ReadAllText((Join-Path $P.Root 'HubSpokeC.pas'), $Ascii)
  $hm = [IO.File]::ReadAllText((Join-Path $P.Root 'HubMain.pas'), $Ascii)
  Check 'p2.3 spoke C calls the pointer and uses HubMain.Hub only; HubMain assigns it in initialization' ((Has $sc "HubStampPtr('c');") -and ($sc -notmatch '(?m)^\s+HubMain;') -and ($hm -match '(?s)\ninitialization\r\n  HubStampPtr := HubStamp;')) "$sc`n$hm"
  $left = Get-Cycles $P
  Check 'p2.4 no cycle after a re-index' ($left -match 'No circular unit dependencies found\.') $left
  $E = New-Proj 'hubsurface' 'HubSurface' { param($r) Edit-Text (Join-Path $r 'HubSpokeC.pas') "end;`n`nend." "end;`n`ninitialization`n  HubStamp('init');`n`nend." }
  $o = (Get-HubPlan $E).Out
  Check 'p3 control: a call from the spoke''s initialization keeps the edge (init-order), the group stays' ((Has $o '- `HubSpokeC.pas` keeps `HubStamp`: init-order') -and (Has $o '- uses: 2 spokes drop `HubMain` (edge cut); 1 keep it for other hub symbols: `HubStamp` 1') -and (Has $o 'the group stays -- 1 spoke->hub edges remain')) $o
  $E = New-Proj 'hubsurface' 'HubSurface' { param($r)
    Edit-Text (Join-Path $r 'HubMain.pas') "procedure Run;`n`nimplementation" "procedure Run;`nfunction HubSelf: THubMain;`n`nimplementation"
    Edit-Text (Join-Path $r 'HubMain.pas') "procedure Run;`nbegin" "function HubSelf: THubMain;`nbegin`n  Result:= HubMainForm;`nend;`n`nprocedure Run;`nbegin"
    Edit-Text (Join-Path $r 'HubSpokeC.pas') "  hubMainForm.log.Add(" "  if HubSelf <> nil then`n  hubMainForm.log.Add(" }
  $o = (Get-HubPlan $E).Out
  Check 'p4 control: a routine whose signature names a class of the cycle is refused signature-in-cycle and keeps its spoke''s edge' ((Has $o '- refused routine `HubSelf`: signature-in-cycle') -and (Has $o '1 keep it for other hub symbols: `HubSelf` 1') -and (Has $o 'the group stays')) $o
  $E = New-Proj 'hubsurface' 'HubSurface' { param($r) Edit-Text (Join-Path $r 'HubSpokeA.pas') "  HubMainForm.Counter:= HubMainForm.Counter + 1;" "  HubMainForm.Counter:= HubMainForm.Tag + 1;" }
  $o = (Get-HubPlan $E).Out
  Check 'n5 an ancestor member (Tag): refused member-unsupported, only spoke A refused' ((Has $o '- refused member `Tag`: member-unsupported') -and (Has $o '- refused `HubSpokeA.pas`: member-unsupported') -and ($o -match 'spokes: 2 rewritten')) $o
  $LibDb = 'C:\Projects\.drag-lint\library-Win64.sqlite'
  if (Test-Path -LiteralPath $LibDb) {
    $Anc = { param($r)
      Edit-Text (Join-Path $r 'HubSpokeA.pas') "  HubMainForm.Counter:= HubMainForm.Counter + 1;" "  HubMainForm.Counter:= HubMainForm.Tag + 1;"
      Edit-Text (Join-Path $r 'HubSpokeB.pas') "  if HubMainForm.Ready" "  if HubMainForm.HasParent then HubMainForm.Note('never', 3);`n  if HubMainForm.Ready" }
    $E = New-Proj 'hubsurface' 'HubSurface' $Anc
    $o = (Get-HubPlan $E @() $LibDb).Out
    Check 'p5 with the library: TComponent.Tag (property, rw) and HasParent (method) are on the surface, 0 refused   (RED on 1.48.0: member-unsupported)' ((Has $o '- surface: 6 of 6 members -- 1 read-only (designer fields), 2 read/write (plain fields), 3 methods') -and (Has $o 'property Tag: NativeInt read HubGetTag write HubSetTag;') -and (Has $o 'function HasParent: Boolean;') -and ($o -match 'spokes: 3 rewritten .*, 0 refused') -and (Has $o '- prediction: the group breaks')) $o
    $B = New-Proj 'hubsurface' 'HubSurface' $Anc
    $b0 = Invoke-Build $B
    $out0 = Invoke-Program $B
    $P = New-Proj 'hubsurface' 'HubSurface' $Anc
    $a = Get-HubPlan $P @('--apply') $LibDb
    $b1 = Invoke-Build $P
    $out1 = Invoke-Program $P
    Check 'p6 --apply with the ancestor members: both copies build, stdout byte-identical' (($a.Exit -eq 0) -and $b0.Ok -and $b1.Ok -and ($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) "exit=$($a.Exit) base=[$($b0.Errors)] applied=[$($b1.Errors)] before=[$out0] after=[$out1]"
  } else { Write-Host "  [SKIP] p5/p6: no $LibDb" -ForegroundColor Yellow }
  $K = New-Proj 'guardeduses' 'GuardedUses'
  $k0 = Get-SrcHash $K.Root
  $r = Get-HubPlan $K @('--apply')
  Check 'n6 a two-unit knot: not-hub-shaped (2 hubs), exit 1, nothing written' (($r.Exit -eq 1) -and (Has $r.Out 'refused: not-hub-shaped -- 2 hubs') -and ((Get-SrcHash $K.Root) -eq $k0)) "exit=$($r.Exit) $($r.Out)"
  Write-Host '== q: P6 prep -- the planner asks R3 first under --hub-surface (lane 149 CYA)' -ForegroundColor Cyan
  $o = (Get-HubPlan $P0).Out
  Check 'q1 --plan --hub-surface: the playbook header, the P1 hub block and R3 for the hub group, no Part A for it   (RED on 1.48.0: R3 only, no playbook)' ((Has $o '# Cycle refactoring playbook') -and (Has $o '## Group 1 (4 units): hub-shaped -- recipe R3 in place of Part A / Part B (--hub-surface)') -and ($o -match 'hub hubmain: in 3 edges') -and (Has $o '## Group 1 (4 units): hub-surface recipe R3') -and ($o -notmatch '## Cycle 1:') -and ($o -notmatch 'Untangle')) $o
  $o = (Get-HubPlan $K).Out
  Check 'q2 control: a knot R3 refuses gets the note and the planner''s own plan' ((Has $o '- group 1: hub-surface recipe R3 refused: not-hub-shaped') -and ($o -match '## Cycle 1:')) $o
  Push-Location $WorkDir
  try {
    $js = ($null | & $Exe cycles --causes --format json --hub-surface --db $P0.Db --library-db none 2>$null | Out-String); $jsCode = $LASTEXITCODE
    $jd = ($null | & $Exe cycles --causes --format json --db $P0.Db --library-db none 2>$null | Out-String)
    $null | & $Exe cycles --format json --hub-surface --db $P0.Db --library-db none *> $null; $badCode = $LASTEXITCODE
  } finally { Pop-Location }
  $fx = $null; try { $fx = ($js | ConvertFrom-Json)[0].fix } catch { }
  Check 'q3 --causes --format json --hub-surface: the fix object is R3''s (part r3, available, 3 cut edges, its commands)   (RED on 1.48.0: exit 2)' (($jsCode -eq 0) -and ($null -ne $fx) -and ($fx.part -eq 'r3') -and ($fx.recipe -eq 'hub-surface') -and ($fx.available -eq $true) -and (@($fx.edges).Count -eq 3) -and ($fx.apply -match '--hub-surface .*--cycle 1 --apply$')) "exit=$jsCode $js"
  $fd = $null; try { $fd = ($jd | ConvertFrom-Json)[0].fix } catch { }
  Check 'q4 control: without --hub-surface the fix object is the planner''s (default unchanged)' (($null -ne $fd) -and ($fd.part -ne 'r3') -and ($fd.dry_run -match '--fix')) $jd
  Check 'q5 --format json --hub-surface without --causes: exit 2' ($badCode -eq 2) "exit=$badCode"} finally {
  if (-not $KeepWorkDir) {
    for ($i = 0; ($i -lt 15) -and (Test-Path -LiteralPath $WorkDir); $i++) {
      try { [IO.Directory]::Delete($WorkDir, $true) } catch { Start-Sleep -Seconds 2 }
    }
  }
}
Write-Host ("run_cyclefix_hubsurface_dcc: {0} ({1} checks)" -f ($(if ($script:Failed) { 'FAIL' } else { 'PASS' })), $script:Passed)
if ($script:Failed) { exit 1 } else { exit 0 }
