<#
  run_cyclefix_r1.ps1 -- E18 Task 5: recipe R1, routine-call inversion, in `cycles --plan`.

  An implementation-only cycle none of whose edges can MOVE is cut on an edge that is exactly
  one routine whose signature types all live outside the cycle: the consumer calls it through a
  procedural variable `<Routine>Ptr` of type `T<Routine>Ptr = function(<signature verbatim>)`,
  declared in a leaf and assigned in the declaring unit's initialization section.

  (a) circular-demo copy, cycle 3: Step 4 equals tests\fixtures\cyclefix\oracle\demo-plan-r1.txt
      (blank and comment lines ignored; @@ROOT@@ = the copy); the plan is mechanical (plan dump);
      tools\follow-cycle-plan.ps1 applies it (exit 0); re-indexed, `cycles` prints 2 groups
      ([4 units], [2 units]) -- the plan's own prediction. The leaf is the EXISTING
      DemoBlueprint.Interfaces (J2: both ends use it in their interface; it declares the result type).
  (b) tests\fixtures\cyclefix\initorder: DemoBlueprint's initialization calls Show, which makes the
      call -- `refused: init-order`. POSITIVE CONTROL: the same copy without the `Show` line in the
      initialization section is cut by R1 -- so the refusal comes from the initialization text.
  (c) tests\fixtures\cyclefix\sigincycle: the routine returns a class of the cycle --
      `refused: signature-in-cycle` naming it.
  (d) tests\fixtures\cyclefix\r1extend: a System-types-only signature (no J2 leaf) and an EXISTING
      R1Title.Untangle: it is EXTENDED (insert after its last interface declaration, no repeated
      `type`, System.SysUtils merged into a new interface uses clause); followed + re-indexed, no
      cycle remains.
  (e) POSITIVE CONTROL for (d): that leaf already declaring `TR1TitleOfPtr` -- `refused:
      duplicate-identifier`, nothing inserted.
  (f) r1extend without R1Title.Untangle: the leaf is CREATED and registered; followed + re-indexed,
      no cycle remains.
  Fix round 1 (each refusal check was RED with its refusal disabled):
  (g) tests\fixtures\cyclefix\r1stdcall: the pointer type carries `stdcall;`.
  (h) `overload;` on a single routine is a neutral directive: still mechanical, nothing carried.
  (i) `cdecl; varargs;` -- `refused: unsupported-directive`.
  (j) a second, unit-qualified call `R1Title.R1TitleOf(...)` -- `refused: qualified-ref` (the cut would
      remove the uses entry that call needs).
  (k) a second overload in R1Title -- `refused: overloaded-routine` (the index binds an overload's
      call by name; the pointer type could mirror the wrong signature -- E2010 seen).
  Fix round 2 (RED on the round-1 engine / with the refusal disabled):
  (l) tests\fixtures\cyclefix\r1stillused: TR1Form calls its INHERITED class method R1Note; the
      planner binds the bare name to R1Title.R1Note -- `refused: edge-still-used`.
  (n) `export; stdcall;` -- an unclassified directive refuses (stdcall is no longer silently lost).
  (o) `R1Title.R1TitleCount` -- any name qualified by the declaring unit refuses `qualified-ref`.
  (p) `TR1Local.R1TitleOf` -- a same-named method through a non-unit receiver does NOT refuse.
  The compile of every applied tree is run_cyclefix_r1_dcc.ps1 (needs RAD Studio).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-r1-$PID"
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
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fx    = Join-Path $Repo 'tests\fixtures\cyclefix'
$Ascii = [Text.Encoding]::ASCII

# Copies the .pas / .dpr / .dproj files of pFrom into a new dir pTo.
function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}

# Rewrites one file of a copy (CRLF, ASCII).
function Set-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii)
}

function Invoke-Index([string]$Dproj, [string]$Db, [string]$Tag) {
  & $Exe index --project $Dproj --db $Db *> (Join-Path $WorkDir "index-$Tag.log")
  return $LASTEXITCODE
}

# Runs `cycles` (with pExtra) on pDb; stdout to a file; the plan dump (DRAGLINT_TEST_DUMP_PLAN) parsed per cycle.
function Get-Cycles([string]$Db, [string]$Tag, [string[]]$Extra) {
  $o = Join-Path $WorkDir "cycles-$Tag.out"
  $dump = Join-Path $WorkDir "dump-$Tag.txt"
  $env:DRAGLINT_TEST_DUMP_PLAN = $dump
  try {
    $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
      -ArgumentList (@('cycles', '--db', ('"' + $Db + '"')) + $Extra + $(if ($Extra -contains '--plan') { @('--library-db', 'none') } else { @() })) `
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

# The lines of cycle pNo's block in a plan.
function Get-CycleBlock([string]$Plan, [int]$No) {
  $out = @(); $in = $false
  foreach ($l in @($Plan -split "`r?`n")) {
    if ($l -match '^## Cycle (\d+):') { $in = ([int]$Matches[1] -eq $No); continue }
    if ($in) { $out += $l }
  }
  return ,$out
}

# Step 4 of a cycle block (or an oracle file) from its first file heading on, without blank lines,
# Pascal comment lines and `# ` comment lines.
function Get-Step4([string[]]$Blk) {
  $out = @(); $in = $false; $files = $false
  foreach ($l in $Blk) {
    if ($l -match '^### Step 4') { $in = $true; continue }
    if ($in -and $l -match '^### ') { break }
    if (-not $in) { continue }
    if ($l -match '^#### ') { $files = $true }
    if (-not $files) { continue }
    $t = $l.Trim()
    if ($t -eq '' -or $t.StartsWith('//') -or $l.StartsWith('# ')) { continue }
    $out += $l.TrimEnd()
  }
  return ,$out
}

# The edits Step 4 lists for one file.
function Get-FileEdits([string[]]$Blk, [string]$FileName) {
  $out = @(); $in = $false
  foreach ($l in $Blk) {
    if ($l -match '^####? ') { $in = $l.StartsWith('#### `' + $FileName + '`  ('); continue }
    if ($in) { $out += $l }
  }
  return ,$out
}

# The unit names Step 3 of a cycle block creates.
function Get-NewUnits([string[]]$Blk) {
  $out = @(); $in = $false
  foreach ($l in $Blk) {
    if ($l -match '^### Step 3') { $in = $true; continue }
    if ($l -match '^### ') { $in = $false }
    if ($in -and $l -match '^#### `([^`]+)` -> `') { $out += $Matches[1] }
  }
  return ,$out
}

# The group lines of a `cycles` text report, members sorted, as one string.
function Get-Groups([string[]]$Lines) {
  $g = foreach ($l in $Lines) {
    if ($l -match '^\s*\[(\d+) units\] (.+?)   (\(.+\))\s*$') {
      $m = @($Matches[2] -split ' <-> ' | Sort-Object) -join ','
      "[$($Matches[1])] $m $($Matches[3])"
    } elseif ($l -match '^\d+ circular unit group\(s\) found:$|^No circular unit dependencies found\.$') { $l }
  }
  return (@($g | Sort-Object) -join ' | ')
}

# The output the plan's last checklist item says `cycles` must print.
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

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  # --- (a) the demo, cycle 3 ------------------------------------------------------------------
  Write-Host '== (a) circular-demo cycle 3: routine-call inversion into DemoBlueprint.Interfaces' -ForegroundColor Cyan
  $demo = Join-Path $WorkDir 'circular-demo'
  Copy-Tree (Join-Path $Repo 'circular-demo') $demo
  $dbA = Join-Path $WorkDir 'demo.sqlite'
  Check 'a0 demo indexed' ((Invoke-Index (Join-Path $demo 'CircularDemo.dproj') $dbA 'a') -eq 0)
  $pa = Get-Cycles $dbA 'a' @('--plan')
  Check 'a1 cycles --plan exit 0' ($pa.Exit -eq 0) "exit=$($pa.Exit)"
  $blkA = Get-CycleBlock $pa.Out 3
  $oracle = [IO.File]::ReadAllText((Join-Path $Fx 'oracle\demo-plan-r1.txt')).Replace('@@ROOT@@', $demo)
  $want = Get-Step4 @($oracle -split "`r?`n")
  $got  = Get-Step4 $blkA
  $same = ($want.Count -gt 0) -and (($got -join "`n") -ceq ($want -join "`n"))
  $diff = ''
  if (-not $same) {
    for ($k = 0; $k -lt [Math]::Max($got.Count, $want.Count); $k++) {
      if ($got[$k] -cne $want[$k]) { $diff = "line $($k + 1): got [$($got[$k])] want [$($want[$k])]"; break }
    }
  }
  Check 'a2 Step 4 of cycle 3 equals the oracle (blank / comment lines ignored)' $same $diff
  $broken = @($want); if ($broken.Count -gt 2) { $broken[2] = $broken[2] + ' ' }
  Check 'a2c positive control: a one-line oracle change is detected' (($got -join "`n") -cne ($broken -join "`n")) ''
  $d3 = $pa.Dump[3]
  Check 'a3 the plan of cycle 3 is mechanical, no refusal (plan dump)' (($null -ne $d3) -and ($d3.verdict -eq 'mechanical') -and ($d3.refusals -eq '')) ("[$($d3.verdict) / $($d3.refusals)]")
  $fo = Invoke-Follow $pa.File 3 $demo
  Check 'a4 the follower applies cycle 3 (exit 0)' ($fo.Exit -eq 0) ("exit=$($fo.Exit) $($fo.Text)")
  $intf = [IO.File]::ReadAllText((Join-Path $demo 'DemoBlueprint.Interfaces.pas'))
  Check 'a5 the pointer type mirrors the signature verbatim (J3)' `
    ($intf.Contains('  TDemoBlueprintViewModelCreatePtr = function(const pFolderId: Integer): IDemoBlueprintViewModel;')) ''
  $vm = [IO.File]::ReadAllText((Join-Path $demo 'DemoBlueprint.ViewModel.pas'))
  Check 'a6 DemoBlueprint.ViewModel assigns it in a new initialization section' `
    ($vm -match "(?s)initialization\r\n  DemoBlueprintViewModelCreatePtr := DemoBlueprintViewModelCreate;\r\n\r\nend\.\r?\n?$") ''
  $bp = [IO.File]::ReadAllText((Join-Path $demo 'DemoBlueprint.pas'))
  Check 'a7 DemoBlueprint no longer names DemoBlueprint.ViewModel' (-not $bp.Contains('DemoBlueprint.ViewModel;') -and $bp.Contains('DemoBlueprintViewModelCreatePtr(FFolderId)')) ''
  Check 'a8 re-indexed' ((Invoke-Index (Join-Path $demo 'CircularDemo.dproj') $dbA 'a2') -eq 0)
  $after = Get-Cycles $dbA 'a-after' @()
  $gA = Get-Groups @($after.Out -split "`r?`n"); $gP = Get-Groups (Get-Predicted $blkA)
  Check 'a9 `cycles` prints 2 groups, [4] and [2], as the plan predicts' `
    (($gA -match '(^| )2 circular unit group') -and ($gA -match '\[4\] ') -and ($gA -match '\[2\] ') -and ($gA -notmatch '\[3\] ') -and ($gA -eq $gP)) "actual [$gA] predicted [$gP]"

  # --- (b) init-order -------------------------------------------------------------------------
  Write-Host '== (b) initorder: the call is reachable from an initialization section' -ForegroundColor Cyan
  $ib = Join-Path $WorkDir 'initorder'
  Copy-Tree (Join-Path $Fx 'initorder') $ib
  $dbB = Join-Path $WorkDir 'initorder.sqlite'
  Check 'b0 indexed' ((Invoke-Index (Join-Path $ib 'InitOrder.dproj') $dbB 'b') -eq 0)
  $pb = Get-Cycles $dbB 'b' @('--plan')
  $txB = (Get-CycleBlock $pb.Out 1) -join "`n"
  Check 'b1 the routine edge is refused: init-order' ($txB.Contains('`DemoBlueprintViewModelCreate` (function): refused: init-order -- `Show`')) ''
  Check 'b2 the plan is refused with init-order (plan dump) and prints no Step 4' `
    (($pb.Dump[1].verdict -eq 'refused') -and (($pb.Dump[1].refusals -split ',') -contains 'init-order') -and -not $txB.Contains('### Step 4')) ("[$($pb.Dump[1].verdict) / $($pb.Dump[1].refusals)]")
  $ic = Join-Path $WorkDir 'initorder-control'
  Copy-Tree (Join-Path $Fx 'initorder') $ic
  $bpC = Join-Path $ic 'DemoBlueprint.pas'
  $t = [IO.File]::ReadAllText($bpC)
  Set-Text $bpC ($t.Replace("  GStartupDrawing.Show;`r`n", ''))
  $dbC = Join-Path $WorkDir 'initorder-control.sqlite'
  Check 'b3 control copy indexed' (([IO.File]::ReadAllText($bpC) -ne $t) -and ((Invoke-Index (Join-Path $ic 'InitOrder.dproj') $dbC 'bc') -eq 0))
  $pc = Get-Cycles $dbC 'bc' @('--plan')
  $txC = (Get-CycleBlock $pc.Out 1) -join "`n"
  Check 'b4 positive control: without `Show` in the initialization the same edge IS cut by R1' `
    ($txC.Contains('by **routine-call inversion**') -and -not $txC.Contains('init-order') -and ($pc.Dump[1].verdict -eq 'mechanical')) ''

  # --- (c) signature-in-cycle -------------------------------------------------------------------
  Write-Host '== (c) sigincycle: the routine returns a class of the cycle' -ForegroundColor Cyan
  $sc = Join-Path $WorkDir 'sigincycle'
  Copy-Tree (Join-Path $Fx 'sigincycle') $sc
  $dbS = Join-Path $WorkDir 'sigincycle.sqlite'
  Check 'c0 indexed' ((Invoke-Index (Join-Path $sc 'SigInCycle.dproj') $dbS 'c') -eq 0)
  $ps = Get-Cycles $dbS 'c' @('--plan')
  $txS = (Get-CycleBlock $ps.Out 1) -join "`n"
  Check 'c1 refused: signature-in-cycle, naming TDemoBlueprintViewModel' `
    ($txS.Contains('refused: signature-in-cycle -- the signature of `DemoBlueprintViewModelCreate` names `TDemoBlueprintViewModel`')) ''
  Check 'c2 the plan is refused with signature-in-cycle (plan dump)' `
    (($ps.Dump[1].verdict -eq 'refused') -and (($ps.Dump[1].refusals -split ',') -contains 'signature-in-cycle')) ("[$($ps.Dump[1].refusals)]")

  # --- (d) an existing Untangle leaf is extended -----------------------------------------------
  Write-Host '== (d) r1extend: R1Title.Untangle exists and is extended' -ForegroundColor Cyan
  $rx = Join-Path $WorkDir 'r1extend'
  Copy-Tree (Join-Path $Fx 'r1extend') $rx
  $dbX = Join-Path $WorkDir 'r1extend.sqlite'
  Check 'd0 indexed' ((Invoke-Index (Join-Path $rx 'R1Extend.dproj') $dbX 'd') -eq 0)
  $px = Get-Cycles $dbX 'd' @('--plan')
  $blkX = Get-CycleBlock $px.Out 1
  $txX = $blkX -join "`n"
  Check 'd1 Step 3: R1Title.Untangle already exists, no new unit' `
    ($txX.Contains('- `R1Title.Untangle` already exists (') -and ((Get-NewUnits $blkX).Count -eq 0)) ''
  $leafTx = (Get-FileEdits $blkX 'R1Title.Untangle.pas') -join "`n"
  Check 'd2 the insert goes after line 10 (its last interface declaration), inside its type block' `
    (($leafTx -match '(?m)^E\d+\. After line 10 \(`TR1TitleStyle = \(tsPlain, tsBold\);`\), insert:') -and
     $leafTx.Contains('  TR1TitleOfPtr = function(const pId: Integer): string;') -and ($leafTx -notmatch '(?m)^type$')) $leafTx
  Check 'd3 the leaf gains System.SysUtils in a new interface uses clause' `
    ($leafTx -match '(?s)After line 6 \(`interface`\), insert:\n```pascal\n\nuses\n  System\.SysUtils;\n```') ''
  $fo = Invoke-Follow $px.File 1 $rx
  Check 'd4 the follower applies it (exit 0)' ($fo.Exit -eq 0) ("exit=$($fo.Exit) $($fo.Text)")
  Check 'd5 no R1Title.Untangle2.pas was created' (-not (Test-Path (Join-Path $rx 'R1Title.Untangle2.pas'))) ''
  Check 'd6 re-indexed' ((Invoke-Index (Join-Path $rx 'R1Extend.dproj') $dbX 'd2') -eq 0)
  $ax = Get-Cycles $dbX 'd-after' @()
  Check 'd7 no cycle remains, as predicted' ((Get-Groups @($ax.Out -split "`r?`n")) -eq 'No circular unit dependencies found.' -and
    ((Get-Groups (Get-Predicted $blkX)) -eq 'No circular unit dependencies found.')) ($ax.Out.Trim())

  # --- (e) positive control: the leaf already declares the pointer type ------------------------
  Write-Host '== (e) positive control: R1Title.Untangle already declares TR1TitleOfPtr' -ForegroundColor Cyan
  $rd = Join-Path $WorkDir 'r1dup'
  Copy-Tree (Join-Path $Fx 'r1extend') $rd
  $lp = Join-Path $rd 'R1Title.Untangle.pas'
  $t = [IO.File]::ReadAllText($lp)
  Set-Text $lp ($t.Replace("  TR1TitleStyle = (tsPlain, tsBold);`r`n", "  TR1TitleStyle = (tsPlain, tsBold);`r`n  TR1TitleOfPtr = Integer;`r`n"))
  $dbD = Join-Path $WorkDir 'r1dup.sqlite'
  Check 'e0 control copy indexed' ((Invoke-Index (Join-Path $rd 'R1Extend.dproj') $dbD 'e') -eq 0)
  $pd = Get-Cycles $dbD 'e' @('--plan')
  $txD = (Get-CycleBlock $pd.Out 1) -join "`n"
  Check 'e1 refused: duplicate-identifier, nothing inserted' `
    ($txD.Contains('refused: duplicate-identifier -- `R1Title.Untangle` already declares `TR1TitleOfPtr`') -and -not $txD.Contains('### Step 4') -and
     (($pd.Dump[1].refusals -split ',') -contains 'duplicate-identifier')) ''

  # --- (f) no leaf yet: R1Title.Untangle is created --------------------------------------------
  Write-Host '== (f) r1extend without R1Title.Untangle: the leaf is created' -ForegroundColor Cyan
  $rf = Join-Path $WorkDir 'r1create'
  Copy-Tree (Join-Path $Fx 'r1extend') $rf
  [IO.File]::Delete((Join-Path $rf 'R1Title.Untangle.pas'))
  $dpr = Join-Path $rf 'R1Extend.dpr'
  Set-Text $dpr ([IO.File]::ReadAllText($dpr).Replace("  R1Title.Untangle in 'R1Title.Untangle.pas',`r`n", '').Replace("    Writeln('[main] style ', Ord(tsBold));`r`n", ''))
  $dpj = Join-Path $rf 'R1Extend.dproj'
  Set-Text $dpj ([IO.File]::ReadAllText($dpj).Replace("        <DCCReference Include=`"R1Title.Untangle.pas`"/>`r`n", ''))
  $dbF = Join-Path $WorkDir 'r1create.sqlite'
  Check 'f0 indexed' ((Invoke-Index $dpj $dbF 'f') -eq 0)
  $pf = Get-Cycles $dbF 'f' @('--plan')
  $blkF = Get-CycleBlock $pf.Out 1
  $txF = $blkF -join "`n"
  Check 'f1 Step 3 creates R1Title.Untangle with the pointer type and System.SysUtils' `
    ((((Get-NewUnits $blkF) -join ',') -eq 'R1Title.Untangle') -and $txF.Contains("type`n  /// <summary>Signature of R1TitleOf (R1Title), copied verbatim.</summary>`n  TR1TitleOfPtr = function(const pId: Integer): string;") -and
     $txF.Contains("interface`n`nuses`n  System.SysUtils;")) ''
  Check 'f2 the .dproj registers it' (((Get-FileEdits $blkF 'R1Extend.dproj') -join "`n").Contains('<DCCReference Include="R1Title.Untangle.pas"/>')) ''
  $fo = Invoke-Follow $pf.File 1 $rf
  Check 'f3 the follower applies it (exit 0) and the unit exists' (($fo.Exit -eq 0) -and (Test-Path (Join-Path $rf 'R1Title.Untangle.pas'))) ("exit=$($fo.Exit) $($fo.Text)")
  Check 'f4 re-indexed' ((Invoke-Index $dpj $dbF 'f2') -eq 0)
  $af = Get-Cycles $dbF 'f-after' @()
  Check 'f5 no cycle remains' ((Get-Groups @($af.Out -split "`r?`n")) -eq 'No circular unit dependencies found.') ($af.Out.Trim())

  # --- (g)-(k) fix round 1: directives, qualified calls, overloads -------------------------------
  # Each case is a copy of r1extend with ONE edit; returns cycle 1's block text and plan dump.
  # An optional second edit (pFile2 / pOld2 / pNew2) goes into another file of the same copy.
  function Get-Variant([string]$Tag, [string]$File, [string]$Old, [string]$New, [string]$File2 = '', [string]$Old2 = '', [string]$New2 = '') {
    $dir = Join-Path $WorkDir $Tag
    Copy-Tree (Join-Path $Fx 'r1extend') $dir
    $p = Join-Path $dir $File
    $t = [IO.File]::ReadAllText($p)
    Set-Text $p ($t.Replace($Old, $New))
    $ok2 = $true
    if ($File2 -ne '') {
      $p2 = Join-Path $dir $File2
      $t2 = [IO.File]::ReadAllText($p2)
      Set-Text $p2 ($t2.Replace($Old2, $New2))
      $ok2 = [IO.File]::ReadAllText($p2) -ne $t2
    }
    $db = Join-Path $WorkDir "$Tag.sqlite"
    $okIdx = $ok2 -and ([IO.File]::ReadAllText($p) -ne $t) -and ((Invoke-Index (Join-Path $dir 'R1Extend.dproj') $db $Tag) -eq 0)
    $pl = Get-Cycles $db $Tag @('--plan')
    return @{ Ok = $okIdx; Text = ((Get-CycleBlock $pl.Out 1) -join "`n"); Dump = $pl.Dump[1] }
  }
  $declOld = "function R1TitleOf(const pId: Integer): string;`r`n`r`nimplementation"
  Write-Host '== (g) r1stdcall: the calling convention is carried into the pointer type' -ForegroundColor Cyan
  $sd = Join-Path $WorkDir 'r1stdcall'
  Copy-Tree (Join-Path $Fx 'r1stdcall') $sd
  $dbSd = Join-Path $WorkDir 'r1stdcall.sqlite'
  Check 'g0 indexed' ((Invoke-Index (Join-Path $sd 'R1Extend.dproj') $dbSd 'g') -eq 0)
  $pg = Get-Cycles $dbSd 'g' @('--plan')
  $txG = (Get-CycleBlock $pg.Out 1) -join "`n"
  Check 'g1 TR1TitleOfPtr carries `stdcall;`' ($txG.Contains('  TR1TitleOfPtr = function(const pId: Integer): string; stdcall;') -and ($pg.Dump[1].verdict -eq 'mechanical')) ''
  $vh = Get-Variant 'r1neutral' 'R1Title.pas' $declOld "function R1TitleOf(const pId: Integer): string; overload;`r`n`r`nimplementation"
  Check 'h1 a directive that does not change the type (`overload` on a single routine) is skipped, not refused' `
    ($vh.Ok -and ($vh.Dump.verdict -eq 'mechanical') -and $vh.Text.Contains('  TR1TitleOfPtr = function(const pId: Integer): string;' + "`n")) "[$($vh.Dump.verdict) / $($vh.Dump.refusals)]"
  Write-Host '== (i) unsupported directive' -ForegroundColor Cyan
  $vi = Get-Variant 'r1varargs' 'R1Title.pas' $declOld "function R1TitleOf(const pId: Integer): string; cdecl; varargs;`r`n`r`nimplementation"
  Check 'i1 `varargs` on the declaration: refused: unsupported-directive' `
    ($vi.Ok -and $vi.Text.Contains('refused: unsupported-directive -- `R1TitleOf`: the directive `varargs` changes its procedural type') -and
     (($vi.Dump.refusals -split ',') -contains 'unsupported-directive')) "[$($vi.Dump.verdict) / $($vi.Dump.refusals)]"
  Write-Host '== (j) a second, unit-qualified call' -ForegroundColor Cyan
  $vj = Get-Variant 'r1qualified' 'R1Form.pas' "  Writeln(Format('[form] %s', [R1TitleOf(pId)]));" `
    ("  Writeln(Format('[form] %s', [R1TitleOf(pId)]));`r`n  Writeln(R1Title.R1TitleOf(pId + 1));")
  Check 'j1 refused: qualified-ref, naming the qualified line (its uses entry must stay)' `
    ($vj.Ok -and $vj.Text.Contains('refused: qualified-ref -- line 27 names `R1TitleOf` qualified') -and
     (($vj.Dump.refusals -split ',') -contains 'qualified-ref')) "[$($vj.Dump.verdict) / $($vj.Dump.refusals)]"
  Write-Host '== (k) an overloaded routine' -ForegroundColor Cyan
  $vk = Get-Variant 'r1overload' 'R1Title.pas' "/// <summary>Title of one item.</summary>" `
    ("function R1TitleOf(const pName: string): string; overload;`r`n`r`n/// <summary>Title of one item.</summary>")
  Check 'k1 refused: overloaded-routine (the index binds an overload by name)' `
    ($vk.Ok -and $vk.Text.Contains('refused: overloaded-routine -- `R1TitleOf` is overloaded (2 signatures)') -and
     (($vk.Dump.refusals -split ',') -contains 'overloaded-routine')) "[$($vk.Dump.verdict) / $($vk.Dump.refusals)]"
  # --- (l)-(p) fix round 2 ---------------------------------------------------------------------
  Write-Host '== (l) r1stillused: an inherited R1Note keeps R1Title in use by name' -ForegroundColor Cyan
  $su = Join-Path $WorkDir 'r1stillused'
  Copy-Tree (Join-Path $Fx 'r1stillused') $su
  $dbSu = Join-Path $WorkDir 'r1stillused.sqlite'
  Check 'l0 indexed' ((Invoke-Index (Join-Path $su 'R1StillUsed.dproj') $dbSu 'l') -eq 0)
  $pl = Get-Cycles $dbSu 'l' @('--plan')
  $txL = (Get-CycleBlock $pl.Out 1) -join "`n"
  Check 'l1 refused: edge-still-used naming R1Note (the uses entry of R1Title stays)' `
    ($txL.Contains('refused: edge-still-used -- the implementation section of `R1Form.pas` still uses `R1Title`: `R1Note` line 31') -and
     ($pl.Dump[1].verdict -eq 'refused') -and (($pl.Dump[1].refusals -split ',') -contains 'edge-still-used')) "[$($pl.Dump[1].verdict) / $($pl.Dump[1].refusals)]"
  Write-Host '== (n) an unlisted directive before stdcall' -ForegroundColor Cyan
  $vn = Get-Variant 'r1export' 'R1Title.pas' $declOld "function R1TitleOf(const pId: Integer): string; export; stdcall;`r`n`r`nimplementation"
  Check 'n1 `export; stdcall;`: refused: unsupported-directive naming export (stdcall is not silently lost)' `
    ($vn.Ok -and $vn.Text.Contains('refused: unsupported-directive -- `R1TitleOf`: the directive `export` is not one the plan can classify') -and
     (($vn.Dump.refusals -split ',') -contains 'unsupported-directive')) "[$($vn.Dump.verdict) / $($vn.Dump.refusals)]"
  Write-Host '== (o) another symbol named through the unit: R1Title.R1TitleCount' -ForegroundColor Cyan
  $vo = Get-Variant 'r1qualother' 'R1Form.pas' "  Writeln(Format('[form] %s', [R1TitleOf(pId)]));" `
    ("  Writeln(Format('[form] %s', [R1TitleOf(pId)]));`r`n  Writeln(R1Title.R1TitleCount);") `
    'R1Title.pas' "function R1TitleOf(const pId: Integer): string;`r`n`r`nimplementation" `
    ("function R1TitleOf(const pId: Integer): string;`r`n`r`n/// <summary>Number of titles.</summary>`r`n/// <returns>A count.</returns>`r`nfunction R1TitleCount: Integer;`r`n`r`nimplementation")
  Check 'o1 refused: qualified-ref naming R1TitleCount (that use needs the uses entry the cut removes)' `
    ($vo.Ok -and $vo.Text.Contains('refused: qualified-ref -- line 27 names `R1TitleCount` qualified by its unit') -and
     (($vo.Dump.refusals -split ',') -contains 'qualified-ref')) "[$($vo.Dump.verdict) / $($vo.Dump.refusals)]"
  Write-Host '== (p) a same-named method through a non-unit receiver' -ForegroundColor Cyan
  $vp = Get-Variant 'r1objrcv' 'R1Form.pas' "class procedure TR1Form.Open(const pId: Integer);`r`nbegin`r`n" `
    ("type`r`n  TR1Local = class`r`n    class function R1TitleOf: string;`r`n  end;`r`n`r`nclass function TR1Local.R1TitleOf: string;`r`nbegin`r`n  Result := 'local';`r`nend;`r`n`r`nclass procedure TR1Form.Open(const pId: Integer);`r`nbegin`r`n  Writeln(TR1Local.R1TitleOf);`r`n")
  Check 'p1 `TR1Local.R1TitleOf` is no unit-qualified call: still cut by R1, no refusal' `
    ($vp.Ok -and ($vp.Dump.verdict -eq 'mechanical') -and $vp.Text.Contains('by **routine-call inversion**')) "[$($vp.Dump.verdict) / $($vp.Dump.refusals)]"} finally {
  $env:DRAGLINT_TEST_DUMP_PLAN = $null
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
