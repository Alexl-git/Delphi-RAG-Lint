<#
  run_cyclefix_r2.ps1 -- E18 Task 6: recipe R2, member hand-over through an extracted interface,
  in `cycles --plan`.

  An implementation-only cycle none of whose edges can MOVE or be cut by routine-call inversion is
  cut on an edge that is only `is` / `as` against ONE class plus reads of its fields / properties:
  the class implements `I<Class>Surface` (read-only properties for those members, declared in the
  class unit's `<Unit>.Untangle` leaf), the consumer tests with Supports and casts with
  `as I<Class>Surface` -- through the first IInterface ancestor when the receiver's static type
  does not implement IInterface.

  THE PLATFORM LIBRARY: R2 reads class ancestry from it. This runner NEVER lets the engine open
  the real C:\Projects\.drag-lint\library-*.sqlite: it copies -LibraryDb into its $PID scratch dir
  and passes the copy with --library-db on every `cycles --plan`; the no-library cases get a
  STUB library (an index of one empty unit). Check z1 compares size + mtime of the real library
  DBs before and after. Without -LibraryDb on disk it prints SKIP and exits 0.

  (a) circular-demo copy, cycle 2: Steps 3 and 4 equal tests\fixtures\cyclefix\oracle\demo-plan-r2.txt
      (code lines only; blank, comment and prose lines ignored; @@ROOT@@ = the copy; the GUID
      compared by pattern) and the GUID is exactly MD5(`DemoGagePort.Untangle.IDemoGagePortSurface`);
      the plan is mechanical; line 57 becomes `with TComponent(Sender) as IDemoGagePortSurface do`
      (TObject receiver) and line 49 `with Owner as IDemoGagePortSurface do` (TComponent
      receiver); followed and re-indexed, `cycles` prints 2 groups ([4], [3]) as predicted.
  (b) tests\fixtures\cyclefix\memberwrite: `LastGage := 0` inside the `with` -- `refused:
      member-write`. POSITIVE CONTROL: the same copy without that line is cut by R2 (created
      leaf, registered), followed, and no cycle remains.
  (c) tests\fixtures\cyclefix\classmethod: `TDemoGagePort.ClassName` -- `refused: class-method`.
  (d) tests\fixtures\cyclefix\r2extend: the EXISTING DemoGagePort.Untangle is extended (insert after
      its last declaration, inside its type block; a new interface uses clause); followed, no cycle.
  (e) r2extend whose leaf declares nothing (the At=0 anchor of ExtendLeaves): the uses clause leads
      the insert after `interface`; followed, no cycle.
  (f) one mutation of the clean pair per refusal kind (each was RED with the refusal disabled):
      class-method (a method called in the `with` body -- the Review Focus), construction,
      class-ref, type-decl, type-cast, other-ref, multiple-classes, qualified-ref,
      member-unsupported (indexed property), duplicate-identifier (getter / leaf), manual-edit,
      no-iinterface, ref-counted, receiver-unknown, cast-unseen, with-member, ancestry-unknown
      (stub library), leaf-uses-cycle, type-unresolved, edge-still-used.
  (g) the demo with the STUB library: cycle 2 is refused, not cut -- what makes it mechanical
      is the library. (h) an explicit --library-db that does not exist: exit 2.
  The compile of every applied tree is run_cyclefix_r2_dcc.ps1 (needs RAD Studio).
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-r2-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite'
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library DB at $LibraryDb" -ForegroundColor Yellow; exit 0 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fx    = Join-Path $Repo 'tests\fixtures\cyclefix'
$Ascii = [Text.Encoding]::ASCII
$GuidRx = '\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}'

# size + mtime of the real library DBs: the engine must never open (let alone write) them
function Get-LibStamp {
  return (@(Get-ChildItem 'C:\Projects\.drag-lint' -Filter 'library-*.sqlite' -ErrorAction SilentlyContinue |
    Sort-Object Name | ForEach-Object { '{0}={1}@{2:o}' -f $_.Name, $_.Length, $_.LastWriteTimeUtc }) -join ' ')
}

function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}

function Set-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii)
}

function Invoke-Index([string]$Dproj, [string]$Db, [string]$Tag) {
  & $Exe index --project $Dproj --db $Db *> (Join-Path $WorkDir "index-$Tag.log")
  return $LASTEXITCODE
}

# `cycles` (with pExtra) on pDb, stdout to a file; the plan dump (DRAGLINT_TEST_DUMP_PLAN) parsed per cycle.
function Get-Cycles([string]$Db, [string]$Tag, [string[]]$Extra) {
  $o = Join-Path $WorkDir "cycles-$Tag.out"
  $dump = Join-Path $WorkDir "dump-$Tag.txt"
  $env:DRAGLINT_TEST_DUMP_PLAN = $dump
  try {
    $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
      -ArgumentList (@('cycles', '--db', ('"' + $Db + '"')) + $Extra) `
      -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "cycles-$Tag.err")
  } finally {
    $env:DRAGLINT_TEST_DUMP_PLAN = $null
  }
  $byCycle = @{}
  if (Test-Path $dump) {
    foreach ($l in [IO.File]::ReadAllLines($dump)) {
      $h = @{}
      foreach ($kv in ($l -split "`t")) { $i = $kv.IndexOf('='); if ($i -gt 0) { $h[$kv.Substring(0, $i)] = $kv.Substring($i + 1) } }
      if ($h.ContainsKey('cycle')) { $byCycle[[int]$h['cycle']] = $h }
    }
  }
  return @{ Exit = $p.ExitCode; Out = [IO.File]::ReadAllText($o); File = $o; Dump = $byCycle }
}

function Get-Plan([string]$Db, [string]$Tag, [string]$Lib) { return (Get-Cycles $Db $Tag @('--plan', '--library-db', ('"' + $Lib + '"'))) }

function Get-CycleBlock([string]$Plan, [int]$No) {
  $out = @(); $in = $false
  foreach ($l in @($Plan -split "`r?`n")) {
    if ($l -match '^## Cycle (\d+):') { $in = ([int]$Matches[1] -eq $No); continue }
    if ($in) { $out += $l }
  }
  return ,$out
}

# The code of Steps 3 and 4 of a cycle block (or an oracle file): `#### ` headings, `E<n>.` edit
# lines and the lines inside code fences -- without blank lines, Pascal comment lines, `# `
# comments and prose; every GUID replaced by {GUID}.
function Get-Code34([string[]]$Blk) {
  $out = @(); $in = $false; $fence = $false
  foreach ($l in $Blk) {
    if ($l -match '^### Step 3') { $in = $true; continue }
    if ($in -and $l -match '^### Checklist') { break }
    if (-not $in -or $l.StartsWith('# ')) { continue }
    if ($l -match '^```') { $fence = -not $fence; $out += $l.TrimEnd(); continue }
    $t = $l.Trim()
    if ($t -eq '' -or $t.StartsWith('//')) { continue }
    if ($fence -or $l -match '^#### ' -or $l -match '^E\d+\. ') { $out += ($l.TrimEnd() -replace $GuidRx, '{GUID}') }
  }
  return ,$out
}

function Get-FileEdits([string[]]$Blk, [string]$FileName) {
  $out = @(); $in = $false
  foreach ($l in $Blk) {
    if ($l -match '^####? ') { $in = $l.StartsWith('#### `' + $FileName + '`  ('); continue }
    if ($in) { $out += $l }
  }
  return ,$out
}

function Get-NewUnits([string[]]$Blk) {
  $out = @(); $in = $false
  foreach ($l in $Blk) {
    if ($l -match '^### Step 3') { $in = $true; continue }
    if ($l -match '^### ') { $in = $false }
    if ($in -and $l -match '^#### `([^`]+)` -> `') { $out += $Matches[1] }
  }
  return ,$out
}

function Get-Groups([string[]]$Lines) {
  $g = foreach ($l in $Lines) {
    if ($l -match '^\s*\[(\d+) units\] (.+?)   (\(.+\))\s*$') {
      $m = @($Matches[2] -split ' <-> ' | Sort-Object) -join ','
      "[$($Matches[1])] $m $($Matches[3])"
    } elseif ($l -match '^\d+ circular unit group\(s\) found:$|^No circular unit dependencies found\.$') { $l }
  }
  return (@($g | Sort-Object) -join ' | ')
}

function Get-Predicted([string[]]$Blk) {
  $pred = @(); $in = $false
  foreach ($l in $Blk) {
    if ($l -match 'It must print exactly:') { $in = $true; continue }
    if ($in -and $l -eq '```text') { continue }
    if ($in -and $l -eq '```') { break }
    if ($in) { $pred += $l }
  }
  return ,$pred
}

function Invoke-Follow([string]$PlanFile, [int]$Cycle, [string]$Root) {
  $fo = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $PlanFile -Cycle $Cycle -Root $Root 2>&1 | Out-String
  return @{ Exit = $LASTEXITCODE; Text = ($fo.Trim() -replace "`r?`n", ' | ') }
}

function Get-Md5Guid([string]$Text) {
  $h = [Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))
  $x = ($h | ForEach-Object { $_.ToString('X2') }) -join ''
  return '{' + $x.Substring(0, 8) + '-' + $x.Substring(8, 4) + '-' + $x.Substring(12, 4) + '-' + $x.Substring(16, 4) + '-' + $x.Substring(20, 12) + '}'
}

# A copy of pFrom with each (file, old, new) of pEdits applied; pOk = every edit changed its file.
function New-Variant([string]$From, [string]$Tag, [object[]]$Edits) {
  $dir = Join-Path $WorkDir $Tag
  Copy-Tree $From $dir
  $ok = $true
  foreach ($e in $Edits) {
    $p = Join-Path $dir $e[0]
    if ($e[1] -eq '<new>') { Set-Text $p $e[2]; continue }  # creates a file
    $t = [IO.File]::ReadAllText($p)
    $n = $t.Replace(($e[1] -replace "`r?`n", "`r`n"), ($e[2] -replace "`r?`n", "`r`n"))
    if ($n -eq $t) { $ok = $false }
    Set-Text $p $n
  }
  return @{ Dir = $dir; Ok = $ok }
}

# Indexes a dir with ONE project file and plans it; returns cycle 1's block text, the dump, the file.
function Get-VariantPlan([hashtable]$V, [string]$Tag, [string]$Lib, [int]$Cycle = 1) {
  $dproj = (Get-ChildItem $V.Dir -Filter '*.dproj')[0].FullName
  $db = Join-Path $WorkDir "$Tag.sqlite"
  $okIdx = (Invoke-Index $dproj $db $Tag) -eq 0
  $pl = Get-Plan $db $Tag $Lib
  return @{ Ok = ($V.Ok -and $okIdx); Text = ((Get-CycleBlock $pl.Out $Cycle) -join "`n"); Blk = (Get-CycleBlock $pl.Out $Cycle);
            Dump = $pl.Dump[$Cycle]; File = $pl.File; Db = $db; Dproj = $dproj }
}

$Stamp0 = Get-LibStamp
New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  Write-Host '== setup: library copy and stub library' -ForegroundColor Cyan
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib
  Check 's0 the platform library was copied into the scratch dir' ((Get-Item $Lib).Length -eq (Get-Item $LibraryDb).Length) $Lib
  $stubDir = Join-Path $WorkDir 'stublib'
  New-Item -ItemType Directory -Force $stubDir | Out-Null
  Set-Text (Join-Path $stubDir 'R2Stub.pas') "unit R2Stub;`n`ninterface`n`nimplementation`n`nend.`n"
  $Stub = Join-Path $WorkDir 'stub-library.sqlite'
  & $Exe index $stubDir --db $Stub *> (Join-Path $WorkDir 'index-stub.log')
  Check 's1 a stub library (one empty unit) was indexed' (($LASTEXITCODE -eq 0) -and (Test-Path $Stub)) "exit=$LASTEXITCODE"

  # --- (a) the demo, cycle 2 -----------------------------------------------------------------
  Write-Host '== (a) circular-demo cycle 2: member hand-over into DemoGagePort.Untangle' -ForegroundColor Cyan
  $demo = Join-Path $WorkDir 'circular-demo'
  Copy-Tree (Join-Path $Repo 'circular-demo') $demo
  $dbA = Join-Path $WorkDir 'demo.sqlite'
  Check 'a0 demo indexed' ((Invoke-Index (Join-Path $demo 'CircularDemo.dproj') $dbA 'a') -eq 0)
  $pa = Get-Plan $dbA 'a' $Lib
  Check 'a1 cycles --plan exit 0' ($pa.Exit -eq 0) "exit=$($pa.Exit)"
  $blkA = Get-CycleBlock $pa.Out 2
  $oracle = [IO.File]::ReadAllText((Join-Path $Fx 'oracle\demo-plan-r2.txt')).Replace('@@ROOT@@', $demo)
  $want = Get-Code34 @($oracle -split "`r?`n")
  $got  = Get-Code34 $blkA
  $same = ($want.Count -gt 0) -and (($got -join "`n") -ceq ($want -join "`n"))
  $diff = ''
  if (-not $same) {
    for ($k = 0; $k -lt [Math]::Max($got.Count, $want.Count); $k++) {
      if ($got[$k] -cne $want[$k]) { $diff = "line $($k + 1): got [$($got[$k])] want [$($want[$k])]"; break }
    }
  }
  Check 'a2 Steps 3-4 of cycle 2 equal the oracle (code lines; GUID by pattern)' $same $diff
  $broken = @($want); if ($broken.Count -gt 5) { $broken[5] = $broken[5] + ' ' }
  Check 'a2c positive control: a one-line oracle change is detected' (($got -join "`n") -cne ($broken -join "`n")) ''
  $txA = $blkA -join "`n"
  $guid = Get-Md5Guid 'DemoGagePort.Untangle.IDemoGagePortSurface'
  Check 'a3 the GUID is MD5(`DemoGagePort.Untangle.IDemoGagePortSurface`) as {8-4-4-4-12}' ($txA.Contains("    ['$guid']")) $guid
  $d2 = $pa.Dump[2]
  Check 'a4 the plan of cycle 2 is mechanical, no refusal (plan dump)' (($null -ne $d2) -and ($d2.verdict -eq 'mechanical') -and ($d2.refusals -eq '')) ("[$($d2.verdict) / $($d2.refusals)]")
  $uiTx = (Get-FileEdits $blkA 'DemoUIConnect.pas') -join "`n"
  Check 'a5 line 57 (Sender: TObject) is cast through TComponent' ($uiTx -match "(?s)Replace line 57\. .*?New text:\n``````pascal\n  with TComponent\(Sender\) as IDemoGagePortSurface do\n") ''
  Check 'a6 line 49 (Owner: TComponent) is cast as is' ($uiTx -match "(?s)Replace line 49\. .*?New text:\n``````pascal\n  with Owner as IDemoGagePortSurface do\n") ''
  $fo = Invoke-Follow $pa.File 2 $demo
  Check 'a7 the follower applies cycle 2 (exit 0)' ($fo.Exit -eq 0) ("exit=$($fo.Exit) $($fo.Text)")
  $leafP = Join-Path $demo 'DemoGagePort.Untangle.pas'
  $leaf = if (Test-Path $leafP) { [IO.File]::ReadAllText($leafP) } else { '' }
  Check 'a8 DemoGagePort.Untangle carries the interface with read-only properties' `
    ($leaf.Contains('  IDemoGagePortSurface = interface') -and $leaf.Contains('    property Log: TStrings read GetLog;') -and
     $leaf.Contains('    property LastGage: Integer read GetLastGage;') -and $leaf -match "uses`r`n  System\.Classes;") ''
  $gp = [IO.File]::ReadAllText((Join-Path $demo 'DemoGagePort.pas'))
  Check 'a9 TDemoGagePort implements it (heritage + getter bodies)' `
    ($gp.Contains('TDemoGagePort = class(TComponent, IDemoGagePortSurface)') -and $gp.Contains("function TDemoGagePort.GetLog: TStrings;`r`nbegin`r`n  Result := FLog;")) ''
  $ui = [IO.File]::ReadAllText((Join-Path $demo 'DemoUIConnect.pas'))
  $uiCode = (@($ui -split "`r`n" | Where-Object { -not $_.TrimStart().StartsWith('//') }) -join "`n")
  Check 'a10 the code of DemoUIConnect no longer names DemoGagePort or TDemoGagePort' (($uiCode -notmatch '(?m)^\s*DemoGagePort\s*;') -and ($uiCode -notmatch '\bTDemoGagePort\b') -and $ui.Contains('Supports(Sender, IDemoGagePortSurface)')) ''
  Check 'a11 re-indexed' ((Invoke-Index (Join-Path $demo 'CircularDemo.dproj') $dbA 'a2') -eq 0)
  $after = Get-Cycles $dbA 'a-after' @()
  $gA = Get-Groups @($after.Out -split "`r?`n"); $gP = Get-Groups (Get-Predicted $blkA)
  Check 'a12 `cycles` prints 2 groups, [4] and [3], as the plan predicts' `
    (($gA -match '(^| )2 circular unit group') -and ($gA -match '\[4\] ') -and ($gA -match '\[3\] ') -and ($gA -notmatch '\[2\] ') -and ($gA -eq $gP)) "actual [$gA] predicted [$gP]"

  # --- (b) memberwrite + its positive control ---------------------------------------------------
  Write-Host '== (b) memberwrite: a write inside the `with` body' -ForegroundColor Cyan
  $vb = Get-VariantPlan (New-Variant (Join-Path $Fx 'memberwrite') 'memberwrite' @()) 'b' $Lib
  Check 'b1 refused: member-write, naming line 65 and LastGage; no Step 4' `
    ($vb.Ok -and $vb.Text.Contains('refused: member-write -- line 65 writes `LastGage`') -and ($vb.Dump.verdict -eq 'refused') -and
     (($vb.Dump.refusals -split ',') -contains 'member-write') -and -not $vb.Text.Contains('### Step 4')) "[$($vb.Dump.verdict) / $($vb.Dump.refusals)]"
  $Clean = @(, @('DemoUIConnect.pas', "    LastGage := 0; // <-- a WRITE through the with: an interface of reads cannot carry it`n", ''))
  $vc = Get-VariantPlan (New-Variant (Join-Path $Fx 'memberwrite') 'clean' $Clean) 'bc' $Lib
  Check 'b2 positive control: without the write the same pair IS cut by R2 (leaf created)' `
    ($vc.Ok -and $vc.Text.Contains('by **member hand-over through an extracted interface**') -and ($vc.Dump.verdict -eq 'mechanical') -and
     (((Get-NewUnits $vc.Blk) -join ',') -eq 'DemoGagePort.Untangle') -and ((Get-FileEdits $vc.Blk 'MemberWrite.dproj') -join "`n").Contains('<DCCReference Include="DemoGagePort.Untangle.pas"/>')) "[$($vc.Dump.verdict) / $($vc.Dump.refusals)]"
  $fo = Invoke-Follow $vc.File 1 (Join-Path $WorkDir 'clean')
  Check 'b3 the follower applies it (exit 0)' ($fo.Exit -eq 0) ("exit=$($fo.Exit) $($fo.Text)")
  Check 'b4 re-indexed' ((Invoke-Index $vc.Dproj $vc.Db 'bc2') -eq 0)
  $ac = Get-Cycles $vc.Db 'bc-after' @()
  Check 'b5 no cycle remains' ((Get-Groups @($ac.Out -split "`r?`n")) -eq 'No circular unit dependencies found.') ($ac.Out.Trim())

  # --- (c) classmethod ---------------------------------------------------------------------------
  Write-Host '== (c) classmethod: TDemoGagePort.ClassName' -ForegroundColor Cyan
  $vcm = Get-VariantPlan (New-Variant (Join-Path $Fx 'classmethod') 'classmethod' @()) 'c' $Lib
  Check 'c1 refused: class-method, naming ClassName' `
    ($vcm.Ok -and $vcm.Text.Contains('refused: class-method -- line 54 calls `ClassName` through the class `TDemoGagePort`') -and
     (($vcm.Dump.refusals -split ',') -contains 'class-method')) "[$($vcm.Dump.verdict) / $($vcm.Dump.refusals)]"

  # --- (d) an existing leaf is extended -----------------------------------------------------------
  Write-Host '== (d) r2extend: DemoGagePort.Untangle exists and is extended' -ForegroundColor Cyan
  $vd = Get-VariantPlan (New-Variant (Join-Path $Fx 'r2extend') 'r2extend' @()) 'd' $Lib
  Check 'd1 Step 3: DemoGagePort.Untangle already exists and receives the interface; no new unit' `
    ($vd.Ok -and $vd.Text.Contains('- `DemoGagePort.Untangle` already exists (') -and $vd.Text.Contains('it receives the interface `IDemoGagePortSurface`') -and
     ((Get-NewUnits $vd.Blk).Count -eq 0) -and ($vd.Dump.verdict -eq 'mechanical')) "[$($vd.Dump.verdict) / $($vd.Dump.refusals)]"
  $leafTx = (Get-FileEdits $vd.Blk 'DemoGagePort.Untangle.pas') -join "`n"
  Check 'd2 the interface goes after line 11 (TDemoGageUnit), inside its type block' `
    (($leafTx -match '(?m)^E\d+\. After line 11 \(`TDemoGageUnit = \(guMillimetre, guInch\);`\), insert:') -and
     $leafTx.Contains('  IDemoGagePortSurface = interface') -and ($leafTx -notmatch '(?m)^type$')) $leafTx
  Check 'd3 the leaf gains System.Classes in a new interface uses clause' `
    ($leafTx -match '(?s)After line 7 \(`interface`\), insert:\n```pascal\n\nuses\n  System\.Classes;\n```') ''
  $fo = Invoke-Follow $vd.File 1 (Join-Path $WorkDir 'r2extend')
  Check 'd4 the follower applies it (exit 0); no second leaf' (($fo.Exit -eq 0) -and -not (Test-Path (Join-Path $WorkDir 'r2extend\DemoGagePort.Untangle2.pas'))) ("exit=$($fo.Exit) $($fo.Text)")
  Check 'd5 re-indexed' ((Invoke-Index $vd.Dproj $vd.Db 'd2') -eq 0)
  $ad = Get-Cycles $vd.Db 'd-after' @()
  Check 'd6 no cycle remains' ((Get-Groups @($ad.Out -split "`r?`n")) -eq 'No circular unit dependencies found.') ($ad.Out.Trim())

  # --- (e) an existing leaf that declares nothing: the At=0 anchor --------------------------------
  Write-Host '== (e) r2extend whose leaf declares nothing (ExtendLeaves At=0)' -ForegroundColor Cyan
  $At0 = @(@('DemoGagePort.Untangle.pas', "type`n  /// <summary>The unit a gage reads in.</summary>`n  TDemoGageUnit = (guMillimetre, guInch);`n`n", ''),
           @('R2Extend.dpr', "    Writeln('[main] unit ', Ord(guInch));`n", ''))
  $ve = Get-VariantPlan (New-Variant (Join-Path $Fx 'r2extend') 'r2at0' $At0) 'e' $Lib
  $leafE = (Get-FileEdits $ve.Blk 'DemoGagePort.Untangle.pas') -join "`n"
  Check 'e1 one insert after `interface`, led by the new uses clause, then `type` and the interface' `
    ($ve.Ok -and ($ve.Dump.verdict -eq 'mechanical') -and
     ($leafE -match '(?s)^E1\. After line 7 \(`interface`\), insert:\n```pascal\n\nuses\n  System\.Classes;\n\ntype\n.*  IDemoGagePortSurface = interface') -and
     ($leafE -notmatch '(?m)^E2\.')) $leafE
  $fo = Invoke-Follow $ve.File 1 (Join-Path $WorkDir 'r2at0')
  Check 'e2 the follower applies it (exit 0)' ($fo.Exit -eq 0) ("exit=$($fo.Exit) $($fo.Text)")
  Check 'e3 re-indexed' ((Invoke-Index $ve.Dproj $ve.Db 'e2') -eq 0)
  $ae = Get-Cycles $ve.Db 'e-after' @()
  Check 'e4 no cycle remains' ((Get-Groups @($ae.Out -split "`r?`n")) -eq 'No circular unit dependencies found.') ($ae.Out.Trim())

  # --- (f) one mutation of the clean pair per refusal kind ----------------------------------------
  Write-Host '== (f) refusal kinds (clean pair + one mutation each)' -ForegroundColor Cyan
  $cleanDir = Join-Path $WorkDir 'clean-src'
  $null = New-Variant (Join-Path $Fx 'memberwrite') 'clean-src' $Clean
  $U = 'DemoUIConnect.pas'; $G = 'DemoGagePort.pas'
  $InfoDecl = "  /// <summary>Describes a gage.</summary>`n  TDemoGageInfo = class`n  public`n    type`n      /// <summary>How a reading is scaled.</summary>`n      TKind = (gkPlain, gkScaled);`n  end;`n"
  $KindMember = @(@($G, '    FLastGage: Integer;', "    FLastGage: Integer;`n    FKind: TDemoGageInfo.TKind;"),
    @($G, '    property LastGage: Integer read FLastGage write FLastGage;', "    property LastGage: Integer read FLastGage write FLastGage;`n    /// <summary>The scaling.</summary>`n    property Kind: TDemoGageInfo.TKind read FKind;"),
    @($U, "    Log.Add('data ' + InBuf);", "    Log.Add('data ' + InBuf + IntToStr(Ord(Kind)));"))
  $NestedIn = @(, @($G, "type`n  /// <summary>Stand-in for the gage-port form", "type`n$InfoDecl`n  /// <summary>Stand-in for the gage-port form")) + $KindMember
  $NestedOut = @(@('DemoGageKinds.pas', '<new>', "unit DemoGageKinds;`n`n// E18 T6 fix round 1 variant: a unit outside the cycle that declares a nested type.`n`ninterface`n`ntype`n$InfoDecl`nimplementation`n`nend.`n"),
    @($G, "  System.Classes;`n`ntype", "  System.Classes,`n  DemoGageKinds;`n`ntype"),
    @('MemberWrite.dpr', "  DemoGagePort in 'DemoGagePort.pas',", "  DemoGageKinds in 'DemoGageKinds.pas',`n  DemoGagePort in 'DemoGagePort.pas',"),
    @('MemberWrite.dproj', '        <DCCReference Include="DemoGagePort.pas"/>', "        <DCCReference Include=`"DemoGageKinds.pas`"/>`n        <DCCReference Include=`"DemoGagePort.pas`"/>")) + $KindMember
  $AttachGuarded = "  if not (Owner is TDemoGagePort) then`n    Exit;`n  with Owner as TDemoGagePort do`n    Log.Add(Format('ui connected (last gage %d)', [LastGage]));`n"
  $AttachTryUnguarded = "  try`n    with Owner as TDemoGagePort do`n      Log.Add(Format('ui connected (last gage %d)', [LastGage]));`n  except`n    on EInvalidCast do`n      Exit;`n  end;`n"
  $AttachTryGuarded = "  if not (Owner is TDemoGagePort) then`n    Exit;`n  try`n    with Owner as TDemoGagePort do`n      Log.Add(Format('ui connected (last gage %d)', [LastGage]));`n  except`n    on EInvalidCast do`n      Exit;`n  end;`n"
  $Cases = @(
    @('f1', 'class-method', 'line 65 calls the method `ReadGage`', $cleanDir, @(, @($U, "    Log.Add(Format('gage now %d', [LastGage]));`n  end;", "    Log.Add(Format('gage now %d', [LastGage]));`n    ReadGage(1);`n  end;"))),
    @('f2', 'construction', 'line 52 constructs `TDemoGagePort`', $cleanDir, @(, @($U, '  with Owner as TDemoGagePort do', "  TDemoGagePort.Create(nil).Free;`n  with Owner as TDemoGagePort do"))),
    @('f3', 'class-ref', 'passes the class `TDemoGagePort` as a value', $cleanDir, @(, @($U, '  with Owner as TDemoGagePort do', "  if Owner.ClassType = TDemoGagePort then`n    Exit;`n  with Owner as TDemoGagePort do"))),
    @('f4', 'type-decl', 'declares something of type `TDemoGagePort`', $cleanDir, @(, @($U, "procedure TDemoUIConnect.OnData(Sender: TObject);`nbegin", "procedure TDemoUIConnect.OnData(Sender: TObject);`nvar`n  P: TDemoGagePort;`nbegin`n  P := nil;`n  if P <> nil then`n    Exit;"))),
    @('f5', 'type-cast', 'casts to `TDemoGagePort`', $cleanDir, @(, @($U, "    Log.Add('data ' + InBuf);", "    Log.Add('data ' + InBuf);`n    TDemoGagePort(Sender).Log.Add('cast');"))),
    @('f6', 'other-ref', 'uses `GDemoGageCount`', $cleanDir, @(@($G, "type`n  /// <summary>Stand-in for the gage-port form", "var`n  GDemoGageCount: Integer = 0;`n`ntype`n  /// <summary>Stand-in for the gage-port form"), @($U, '  with Owner as TDemoGagePort do', "  if GDemoGageCount > 0 then`n    Exit;`n  with Owner as TDemoGagePort do"))),
    @('f7', 'multiple-classes', 'the edge names 2 classes', $cleanDir, @(@($G, "  TDemoGagePort = class(TComponent)`n  private", "  TDemoGageAux = class(TComponent)`n  end;`n`n  TDemoGagePort = class(TComponent)`n  private"), @($U, '  with Owner as TDemoGagePort do', "  if Owner is TDemoGageAux then`n    Exit;`n  with Owner as TDemoGagePort do"))),
    @('f8', 'qualified-ref', 'names `TDemoGagePort` qualified by its unit', $cleanDir, @(, @($U, '  if not (Owner is TDemoGagePort) then', '  if not (Owner is DemoGagePort.TDemoGagePort) then'))),
    @('f9', 'member-unsupported', '`TDemoGagePort.Lines` is not a field or a non-indexed property', $cleanDir, @(@($G, '    property LastGage: Integer read FLastGage write FLastGage;', "    property LastGage: Integer read FLastGage write FLastGage;`n    /// <summary>One log line.</summary>`n    property Lines[pIndex: Integer]: string read GetLine;"), @($G, '    FLastGage: Integer;', "    FLastGage: Integer;`n    function GetLine(pIndex: Integer): string;"), @($U, "    Log.Add('data ' + InBuf);", "    Log.Add('data ' + InBuf + Lines[0]);"))),
    @('f10', 'duplicate-identifier', '`TDemoGagePort` already declares `GetLog`', $cleanDir, @(, @($G, '    procedure ReadGage(const pValue: Integer);', "    procedure ReadGage(const pValue: Integer);`n    /// <summary>Already there.</summary>`n    function GetLog: TStrings;"))),
    @('f11', 'duplicate-identifier', '`DemoGagePort.Untangle` already declares `IDemoGagePortSurface`', (Join-Path $Fx 'r2extend'), @(, @('DemoGagePort.Untangle.pas', '  TDemoGageUnit = (guMillimetre, guInch);', "  TDemoGageUnit = (guMillimetre, guInch);`n`n  IDemoGagePortSurface = interface`n  end;"))),
    @('f12', 'manual-edit', 'the heritage of `TDemoGagePort` is not on its declaration line', $cleanDir, @(, @($G, '  TDemoGagePort = class(TComponent)', "  TDemoGagePort = class(`n    TComponent)"))),
    @('f13', 'no-iinterface', 'no ancestor of `TDemoGagePort` implements IInterface', $cleanDir, @(, @($G, '  TDemoGagePort = class(TComponent)', '  TDemoGagePort = class(TObject)'))),
    @('f14', 'ref-counted', 'descends from `TInterfacedObject`, which counts references', $cleanDir, @(, @($G, '  TDemoGagePort = class(TComponent)', '  TDemoGagePort = class(TInterfacedObject)'))),
    @('f15', 'receiver-unknown', 'the static type of `GetOwner`', $cleanDir, @(, @($U, '  with Owner as TDemoGagePort do', '  with GetOwner as TDemoGagePort do'))),
    @('f16', 'cast-unseen', '`TDemoGageBase`, the ancestor a receiver is cast through, is declared in `DemoGagePort`', $cleanDir, @(, @($G, "  TDemoGagePort = class(TComponent)`n  private", "  TDemoGageBase = class(TComponent, IInterface)`n  end;`n`n  TDemoGagePort = class(TDemoGageBase)`n  private"))),
    @('f17', 'with-member', '`Name` at line 63 names a member of `TDemoGagePort` or its ancestors', $cleanDir, @(, @($U, "    Log.Add('data ' + InBuf);", "    Log.Add('data ' + InBuf + Name);"))),
    @('f18', 'ancestry-unknown', 'the ancestry of `TDemoGagePort` stops at `TComponent`', $cleanDir, @(@($U, "  if not (Owner is TDemoGagePort) then`n    Exit;`n  with Owner as TDemoGagePort do`n    Log.Add(Format('ui connected (last gage %d)', [LastGage]));`n", ''), @($U, 'Sender: TObject', 'Sender: TComponent')), 'stub'),
    @('f19', 'leaf-uses-cycle', '`TDemoGageUnit`, the type of `TDemoGagePort.GageUnit`, is declared in `demogageport`', $cleanDir, @(@($G, "type`n  /// <summary>Stand-in", "type`n  /// <summary>Units.</summary>`n  TDemoGageUnit = (guMm, guInch);`n`n  /// <summary>Stand-in"), @($G, '    FLastGage: Integer;', "    FLastGage: Integer;`n    FUnit: TDemoGageUnit;"), @($G, '    property LastGage: Integer read FLastGage write FLastGage;', "    property LastGage: Integer read FLastGage write FLastGage;`n    property GageUnit: TDemoGageUnit read FUnit;"), @($U, "    Log.Add(Format('gage now %d', [LastGage]));", "    Log.Add(Format('gage now %d %d', [LastGage, Ord(GageUnit)]));"))),
    @('f20', 'type-unresolved', 'which unit declares `TNoSuchGauge`', $cleanDir, @(@($G, '    FLastGage: Integer;', "    FLastGage: Integer;`n    FGauge: TNoSuchGauge;"), @($G, '    property LastGage: Integer read FLastGage write FLastGage;', "    property LastGage: Integer read FLastGage write FLastGage;`n    property Gauge: TNoSuchGauge read FGauge;"), @($U, "    Log.Add('data ' + InBuf);", "    Log.Add('data ' + InBuf);`n    if Gauge <> nil then`n      Exit;"))),
    @('f21', 'edge-still-used', 'still uses `DemoGagePort`: `LastGage`', $cleanDir, @(, @($G, "  end;`n`nimplementation", "  end;`n`n/// <summary>A routine named like the member.</summary>`nfunction LastGage: Integer;`n`nimplementation"))),
    # fix round 1: a NESTED member type of a class of the cycle (`TDemoGageInfo.TKind`) -- its owner's unit, never `uses TDemoGageInfo`
    @('f22', 'leaf-uses-cycle', '`TDemoGageInfo.TKind`, the type of `TDemoGagePort.Kind`, is declared in `demogageport`', $cleanDir, $NestedIn),
    # fix round 1: the consumer handles EInvalidCast and casts with an unguarded `as`
    @('f24', 'exception-semantics', 'line 51 casts with `as TDemoGagePort` without an `is` guard', $cleanDir, @(, @($U, $AttachGuarded, $AttachTryUnguarded)))
  )
  foreach ($c in $Cases) {
    $useLib = if ($c.Count -gt 5 -and $c[5] -eq 'stub') { $Stub } else { $Lib }
    $v = Get-VariantPlan (New-Variant $c[3] ('v-' + $c[0]) $c[4]) ('v-' + $c[0]) $useLib
    $kinds = @($v.Dump.refusals -split ',')
    Check ("{0} refused: {1} ({2})" -f $c[0], $c[1], $c[2]) `
      ($v.Ok -and ($v.Dump.verdict -eq 'refused') -and ($kinds -contains $c[1]) -and $v.Text.Contains('refused: ' + $c[1] + ' -- ') -and $v.Text.Contains($c[2])) `
      ("[$($v.Dump.verdict) / $($v.Dump.refusals)] ok=$($v.Ok)")
  }

  # --- fix round 1: positive controls of f22 / f24 ----------------------------------------------
  Write-Host '== (f) fix round 1 controls: a nested type outside the cycle; a guarded cast' -ForegroundColor Cyan
  $v23 = Get-VariantPlan (New-Variant (Join-Path $Fx 'memberwrite') 'v-f23' ($Clean + $NestedOut)) 'v-f23' $Lib
  $leaf23 = $v23.Text
  Check 'f23 a nested member type declared OUTSIDE the cycle: cut, the leaf uses its owner unit DemoGageKinds (never `uses TDemoGageInfo`)' `
    ($v23.Ok -and ($v23.Dump.verdict -eq 'mechanical') -and ($leaf23 -match "(?s)unit DemoGagePort\.Untangle;.*uses\n  System\.Classes,\n  DemoGageKinds;") -and
     ($leaf23 -notmatch '(?m)^  TDemoGageInfo[;,]$') -and $leaf23.Contains('    property Kind: TDemoGageInfo.TKind read GetKind;')) "[$($v23.Dump.verdict) / $($v23.Dump.refusals)]"
  $v25 = Get-VariantPlan (New-Variant $cleanDir 'v-f25' @(, @($U, $AttachGuarded, $AttachTryGuarded))) 'v-f25' $Lib
  Check 'f25 control for f24: EInvalidCast handled, but every `as` follows its `is` guard -- still cut' `
    ($v25.Ok -and ($v25.Dump.verdict -eq 'mechanical') -and $v25.Text.Contains('by **member hand-over through an extracted interface**')) "[$($v25.Dump.verdict) / $($v25.Dump.refusals)]"
  # E18 T6-follow (b): a signature type written `System.Classes.TStrings` while the class unit's uses
  # names `Classes` (unit scope): the longest dotted prefix `System.Classes` is the UNIT, never `System`.
  $v26 = Get-VariantPlan (New-Variant $cleanDir 'v-f26' @(@($G, "  System.Classes;`n`ntype", "  Classes;`n`ntype"),
    @($G, '    property Log: TStrings read FLog;', '    property Log: System.Classes.TStrings read FLog;'))) 'v-f26' $Lib
  Check 'f26 a dotted unit-qualified signature type `System.Classes.TStrings`: cut, the leaf uses System.Classes (never `uses System`)' `
    ($v26.Ok -and ($v26.Dump.verdict -eq 'mechanical') -and ($v26.Text -match "(?s)unit DemoGagePort\.Untangle;.*uses\n  System\.Classes;") -and
     ($v26.Text -notmatch '(?m)^  System[;,]\r?$') -and $v26.Text.Contains('property Log: System.Classes.TStrings read GetLog;')) "[$($v26.Dump.verdict) / $($v26.Dump.refusals)]"
  # T6-follow fix round 1: a type the LIBRARY does not declare (a name made up for the plan) written through the
  # unit scope `System.Classes.` while the uses says `Classes`: the unit comes from the class unit's uses entry
  # under the default unit scope `System` (rule iii), never from the library, and never `uses System`.
  # (`--library-db none` cannot reach the leaf at all: R2 refuses `receiver-unknown`, no ancestry -- see g1 / i2.)
  $v26n = Get-VariantPlan (New-Variant $cleanDir 'v-f26n' @(@($G, "  System.Classes;`n`ntype", "  Classes;`n`ntype"),
    @($G, '    property Log: TStrings read FLog;', '    property Log: System.Classes.TNoSuchInClasses read FLog;'))) 'v-f26n' $Lib
  Check 'f26n a dotted type the library does not declare: cut, the leaf uses System.Classes via the uses entry `Classes` (never `uses System`)' `
    ($v26n.Ok -and ($v26n.Dump.verdict -eq 'mechanical') -and ($v26n.Text -match "(?s)unit DemoGagePort\.Untangle;.*uses\n  System\.Classes;") -and
     ($v26n.Text -notmatch '(?m)^  System[;,]\r?$')) "[$($v26n.Dump.verdict) / $($v26n.Dump.refusals)]"
  # a PROJECT unit with a dotted name declares the member type: the whole dotted prefix is the unit
  $SubUnit = "unit DemoGage.Kinds;`n`n// T6-follow fix round 1 variant: a dotted project unit outside the cycle.`n`ninterface`n`ntype`n  /// <summary>How a reading is scaled.</summary>`n  TGageScale = (gsPlain, gsScaled);`n`nimplementation`n`nend.`n"
  $SubEdits = @(@('DemoGage.Kinds.pas', '<new>', $SubUnit),
    @($G, "  System.Classes;`n`ntype", "  System.Classes,`n  DemoGage.Kinds;`n`ntype"),
    @('MemberWrite.dpr', "  DemoGagePort in 'DemoGagePort.pas',", "  DemoGage.Kinds in 'DemoGage.Kinds.pas',`n  DemoGagePort in 'DemoGagePort.pas',"),
    @('MemberWrite.dproj', '        <DCCReference Include="DemoGagePort.pas"/>', "        <DCCReference Include=`"DemoGage.Kinds.pas`"/>`n        <DCCReference Include=`"DemoGagePort.pas`"/>"),
    @($G, '    FLastGage: Integer;', "    FLastGage: Integer;`n    FScale: DemoGage.Kinds.TGageScale;"),
    @($G, '    property LastGage: Integer read FLastGage write FLastGage;', "    property LastGage: Integer read FLastGage write FLastGage;`n    /// <summary>The scaling.</summary>`n    property Scale: DemoGage.Kinds.TGageScale read FScale;"),
    @($U, "    Log.Add('data ' + InBuf);", "    Log.Add('data ' + InBuf + IntToStr(Ord(Scale)));"))
  $v27 = Get-VariantPlan (New-Variant (Join-Path $Fx 'memberwrite') 'v-f27' ($Clean + $SubEdits)) 'v-f27' $Lib
  Check 'f27 a type of a dotted PROJECT unit `DemoGage.Kinds.TGageScale` (whole dotted prefix is a project stem): cut, the leaf uses DemoGage.Kinds (never `uses DemoGage`)' `
    ($v27.Ok -and ($v27.Dump.verdict -eq 'mechanical') -and ($v27.Text -match "(?s)unit DemoGagePort\.Untangle;.*uses\n  System\.Classes,\n  DemoGage\.Kinds;") -and
     ($v27.Text -notmatch '(?m)^  DemoGage[;,]\r?$') -and $v27.Text.Contains('property Scale: DemoGage.Kinds.TGageScale read GetScale;')) "[$($v27.Dump.verdict) / $($v27.Dump.refusals)]"
  # an unresolvable dotted type (a unit-scope prefix naming no unit): refused, never a `uses System`
  $v28 = Get-VariantPlan (New-Variant $cleanDir 'v-f28' @(@($G, '    FLastGage: Integer;', "    FLastGage: Integer;`n    FGauge: System.NoSuchUnit.TNoSuchGauge;"),
    @($G, '    property LastGage: Integer read FLastGage write FLastGage;', "    property LastGage: Integer read FLastGage write FLastGage;`n    property Gauge: System.NoSuchUnit.TNoSuchGauge read FGauge;"),
    @($U, "    Log.Add('data ' + InBuf);", "    Log.Add('data ' + InBuf);`n    if Gauge <> nil then`n      Exit;"))) 'v-f28' $Lib
  Check 'f28 an unresolvable dotted type `System.NoSuchUnit.TNoSuchGauge`: refused unresolved-qualified-type' `
    ($v28.Ok -and ($v28.Dump.verdict -eq 'refused') -and (@($v28.Dump.refusals -split ',') -contains 'unresolved-qualified-type') -and
     $v28.Text.Contains('refused: unresolved-qualified-type -- ') -and ($v28.Text -notmatch '(?m)^  System[;,]\r?$')) "[$($v28.Dump.verdict) / $($v28.Dump.refusals)]"
  Check 'a13 the demo plan names the exception change of `as` (EInvalidCast -> EIntfCastError)' `
    ($txA.Contains('a failed `as IDemoGagePortSurface` raises EIntfCastError, not EInvalidCast')) ''

  # --- (i) --library-db none ----------------------------------------------------------------------
  Write-Host '== (i) --library-db none opens no library' -ForegroundColor Cyan
  $demoI = Join-Path $WorkDir 'circular-demo-i'
  Copy-Tree (Join-Path $Repo 'circular-demo') $demoI
  $dbI = Join-Path $WorkDir 'demo-i.sqlite'
  $null = Invoke-Index (Join-Path $demoI 'CircularDemo.dproj') $dbI 'i'
  $pi = Get-Cycles $dbI 'i' @('--plan', '--library-db', 'none')
  $errI = [IO.File]::ReadAllText((Join-Path $WorkDir 'cycles-i.err'))
  Check 'i1 `--library-db none`: exit 0, the note says no library, no "reads class ancestry from" line' `
    (($pi.Exit -eq 0) -and $errI.Contains('reads no platform library (--library-db none)') -and -not $errI.Contains('reads class ancestry from')) ($errI.Trim() -replace "`r?`n", ' | ')
  Check 'i2 and cycle 2 is refused, as without a library' (($pi.Dump[2].verdict -eq 'refused') -and ((Get-CycleBlock $pi.Out 2) -join "`n").Contains('`TDemoGagePort` (class): refused: ')) "[$($pi.Dump[2].verdict) / $($pi.Dump[2].refusals)]"
  $errLib = [IO.File]::ReadAllText((Join-Path $WorkDir 'cycles-a.err'))
  Check 'i3 control: with a library given the note names it' ($errLib.Contains('reads class ancestry from ' + $Lib)) ($errLib.Trim() -replace "`r?`n", ' | ')

  # --- (g) the stub library, (h) a missing --library-db ------------------------------------------
  Write-Host '== (g) the demo without the platform library; (h) a missing --library-db' -ForegroundColor Cyan
  $demoG = Join-Path $WorkDir 'circular-demo-g'
  Copy-Tree (Join-Path $Repo 'circular-demo') $demoG
  $dbG = Join-Path $WorkDir 'demo-g.sqlite'
  Check 'g0 a fresh demo copy indexed' ((Invoke-Index (Join-Path $demoG 'CircularDemo.dproj') $dbG 'g') -eq 0)
  $pg = Get-Plan $dbG 'g' $Stub
  Check 'g1 with the stub library cycle 2 is refused, not cut (the library is what makes it mechanical)' `
    (($pg.Dump[2].verdict -eq 'refused') -and ((Get-CycleBlock $pg.Out 2) -join "`n").Contains('`TDemoGagePort` (class): refused: ')) "[$($pg.Dump[2].verdict) / $($pg.Dump[2].refusals)]"
  $ph = Get-Cycles $dbG 'h' @('--plan', '--library-db', ('"' + (Join-Path $WorkDir 'no-such-library.sqlite') + '"'))
  Check 'h1 an explicit --library-db that does not exist: exit 2, ERROR' (($ph.Exit -eq 2) -and $ph.Out.Contains('ERROR: library database not found')) "exit=$($ph.Exit)"
} finally {
  $env:DRAGLINT_TEST_DUMP_PLAN = $null
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
$Stamp1 = Get-LibStamp
Check 'z1 the real library DBs are unchanged (size + mtime)' ($Stamp0 -eq $Stamp1) "before [$Stamp0] after [$Stamp1]"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
