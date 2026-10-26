<#
  run_cyclefix_b3.ps1 -- plan 2026-10-25 (cycles-fix refusal recipes) B3: one edge, several things.
  R1 for N routines on one edge, mixed with movable globals: every top-level owner on the edge is
  either a movable global (it moves into the declaring unit's `<B>.Untangle` leaf, as Part A moves
  it) or an R1-eligible routine (a `T<Routine>Ptr` + `<Routine>Ptr` in that leaf, assigned in ONE
  initialization edit of B with N assignments, every call site rewritten). A signature type of
  the cycle that is a movable plain declaration (enum, record, alias) moves into the leaf first.

  (a) tests\fixtures\cyclefix\r1two: R1Form calls R1TitleOf and R1TitleLen (one line calls both) --
      mechanical, routine-call inversion; the new leaf declares both pointer types and variables;
      the line that calls both is rewritten once with both pointers; R1Title gets one
      initialization edit with both assignments; followed + re-indexed, no cycle remains.
  (b) tests\fixtures\cyclefix\r1mixed: one routine + one const -- the const moves into
      R1Title.Untangle (deleted from R1Title), the routine is called through the pointer;
      followed + re-indexed, no cycle remains.
  (c) tests\fixtures\cyclefix\sigincycleenum: the routine returns an enum of R1Title -- the enum
      moves into the leaf and the pointer type, declared after it, names it; followed +
      re-indexed, no cycle remains.
  POSITIVE CONTROLS:
  (d) tests\fixtures\cyclefix\sigincycle (the routine returns a class with bodies) stays
      `refused: signature-in-cycle`.
  (e) r1two with R1TitleLen `cdecl; varargs;` -- `refused: unsupported-directive` naming R1TitleLen.
  The compile + run of every applied tree is run_cyclefix_r1_dcc.ps1 (needs RAD Studio).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-b3-$PID"
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
  # --- (a) two routines ----------------------------------------------------------------------
  Write-Host '== (a) r1two: two routines on the edge R1Form -> R1Title' -ForegroundColor Cyan
  $ra = Join-Path $WorkDir 'r1two'
  Copy-Tree (Join-Path $Fx 'r1two') $ra
  $dpA = Join-Path $ra 'R1Extend.dproj'
  $dbA = Join-Path $WorkDir 'r1two.sqlite'
  Check 'a0 indexed' ((Invoke-Index $dpA $dbA 'a') -eq 0)
  $pa = Get-Cycles $dbA 'a' @('--plan')
  $blkA = Get-CycleBlock $pa.Out 1
  $txA = $blkA -join "`n"
  Check 'a1 mechanical (plan dump)' ($pa.Dump[1].verdict -eq 'mechanical') "[$($pa.Dump[1].verdict) / $($pa.Dump[1].refusals)]"
  Check 'a2 the edge r1form -> r1title is cut by routine-call inversion' `
    $txA.Contains('- `r1form -> r1title`: recipe: routine-call inversion -- **cut by this plan**') ''
  Check 'a3 Step 3 creates R1Title.Untangle with both pointer types and both variables' `
    ((((Get-NewUnits $blkA) -join ',') -eq 'R1Title.Untangle') -and
     $txA.Contains('  TR1TitleOfPtr = function(const pId: Integer): string;') -and
     $txA.Contains('  TR1TitleLenPtr = function(const pId: Integer): Integer;') -and
     $txA.Contains('  R1TitleOfPtr: TR1TitleOfPtr;') -and $txA.Contains('  R1TitleLenPtr: TR1TitleLenPtr;')) ''
  $formA = (Get-FileEdits $blkA 'R1Form.pas') -join "`n"
  Check 'a4 the line that calls both routines is rewritten once, with both pointers' `
    ($formA.Contains("  Writeln(Format('[form] %d %s', [R1TitleLenPtr(pId), R1TitleOfPtr(pId + 1)]));") -and
     -not $formA.Contains("[R1TitleLenPtr(pId), R1TitleOf(pId + 1)]") -and -not $formA.Contains("[R1TitleLen(pId), R1TitleOfPtr(pId + 1)]")) $formA
  $titleA = (Get-FileEdits $blkA 'R1Title.pas') -join "`n"
  Check 'a5 R1Title gets ONE initialization section with both assignments' `
    (($titleA.Contains("initialization`n  R1TitleOfPtr := R1TitleOf;`n  R1TitleLenPtr := R1TitleLen;")) -and
     ([regex]::Matches($titleA, 'initialization').Count -eq 1)) $titleA
  $fa = Invoke-Follow $pa.File 1 $ra
  Check 'a6 the follower applies it (exit 0)' ($fa.Exit -eq 0) ("exit=$($fa.Exit) $($fa.Text)")
  Check 'a7 re-indexed' ((Invoke-Index $dpA $dbA 'a2') -eq 0)
  $aa = Get-Cycles $dbA 'a-after' @()
  Check 'a8 no cycle remains' ((Get-Groups @($aa.Out -split "`r?`n")) -eq 'No circular unit dependencies found.') ($aa.Out.Trim())

  # --- (b) one routine + one const -------------------------------------------------------------
  Write-Host '== (b) r1mixed: a routine and a const on the edge R1Form -> R1Title' -ForegroundColor Cyan
  $rb = Join-Path $WorkDir 'r1mixed'
  Copy-Tree (Join-Path $Fx 'r1mixed') $rb
  $dpB = Join-Path $rb 'R1Extend.dproj'
  $dbB = Join-Path $WorkDir 'r1mixed.sqlite'
  Check 'b0 indexed' ((Invoke-Index $dpB $dbB 'b') -eq 0)
  $pb = Get-Cycles $dbB 'b' @('--plan')
  $blkB = Get-CycleBlock $pb.Out 1
  $txB = $blkB -join "`n"
  Check 'b1 mechanical (plan dump)' ($pb.Dump[1].verdict -eq 'mechanical') "[$($pb.Dump[1].verdict) / $($pb.Dump[1].refusals)]"
  Check 'b2 the edge r1form -> r1title is cut by routine-call inversion' `
    $txB.Contains('- `r1form -> r1title`: recipe: routine-call inversion -- **cut by this plan**') ''
  Check 'b3 the new leaf holds the const AND the pointer' `
    ((((Get-NewUnits $blkB) -join ',') -eq 'R1Title.Untangle') -and $txB.Contains('  CR1TitleMax = 9;') -and
     $txB.Contains('  TR1TitleOfPtr = function(const pId: Integer): string;')) ''
  $titleB = (Get-FileEdits $blkB 'R1Title.pas') -join "`n"
  Check 'b4 R1Title loses the const and assigns the pointer' `
    ($titleB.Contains('CR1TitleMax = 9;') -and $titleB.Contains('Delete lines') -and $titleB.Contains('  R1TitleOfPtr := R1TitleOf;')) $titleB
  $fb = Invoke-Follow $pb.File 1 $rb
  Check 'b5 the follower applies it (exit 0)' ($fb.Exit -eq 0) ("exit=$($fb.Exit) $($fb.Text)")
  Check 'b6 re-indexed' ((Invoke-Index $dpB $dbB 'b2') -eq 0)
  $ab = Get-Cycles $dbB 'b-after' @()
  Check 'b7 no cycle remains' ((Get-Groups @($ab.Out -split "`r?`n")) -eq 'No circular unit dependencies found.') ($ab.Out.Trim())

  # --- (c) the signature names an enum of the cycle ---------------------------------------------
  Write-Host '== (c) sigincycleenum: the routine returns an enum of R1Title' -ForegroundColor Cyan
  $rc = Join-Path $WorkDir 'sigincycleenum'
  Copy-Tree (Join-Path $Fx 'sigincycleenum') $rc
  $dpC = Join-Path $rc 'R1Extend.dproj'
  $dbC = Join-Path $WorkDir 'sigincycleenum.sqlite'
  Check 'c0 indexed' ((Invoke-Index $dpC $dbC 'c') -eq 0)
  $pc = Get-Cycles $dbC 'c' @('--plan')
  $blkC = Get-CycleBlock $pc.Out 1
  $txC = $blkC -join "`n"
  Check 'c1 mechanical (plan dump)' ($pc.Dump[1].verdict -eq 'mechanical') "[$($pc.Dump[1].verdict) / $($pc.Dump[1].refusals)]"
  $iEnum = $txC.IndexOf('  TR1TitleKind = (tkPlain, tkBold);')
  $iPtr  = $txC.IndexOf('  TR1TitleKindPtr = function(const pId: Integer): TR1TitleKind;')
  Check 'c2 the leaf declares the enum, then the pointer type that names it' (($iEnum -ge 0) -and ($iPtr -gt $iEnum)) "enum@$iEnum ptr@$iPtr"
  $fc = Invoke-Follow $pc.File 1 $rc
  Check 'c3 the follower applies it (exit 0)' ($fc.Exit -eq 0) ("exit=$($fc.Exit) $($fc.Text)")
  Check 'c4 re-indexed' ((Invoke-Index $dpC $dbC 'c2') -eq 0)
  $ac = Get-Cycles $dbC 'c-after' @()
  Check 'c5 no cycle remains' ((Get-Groups @($ac.Out -split "`r?`n")) -eq 'No circular unit dependencies found.') ($ac.Out.Trim())

  # --- (d) positive control: a class with bodies in the signature stays refused --------------------
  Write-Host '== (d) positive control: sigincycle (a class of the cycle in the signature)' -ForegroundColor Cyan
  $rd = Join-Path $WorkDir 'sigincycle'
  Copy-Tree (Join-Path $Fx 'sigincycle') $rd
  $dbD = Join-Path $WorkDir 'sigincycle.sqlite'
  Check 'd0 indexed' ((Invoke-Index (Join-Path $rd 'SigInCycle.dproj') $dbD 'd') -eq 0)
  $pd = Get-Cycles $dbD 'd' @('--plan')
  Check 'd1 still refused: signature-in-cycle' ($pd.Out.Contains('refused: signature-in-cycle')) ''

  # --- (e) positive control: one routine of N with varargs refuses, naming it ----------------------
  Write-Host '== (e) positive control: r1two with R1TitleLen cdecl; varargs;' -ForegroundColor Cyan
  $re = Join-Path $WorkDir 'r1twovarargs'
  Copy-Tree (Join-Path $Fx 'r1two') $re
  $tp = Join-Path $re 'R1Title.pas'
  $old = 'function R1TitleLen(const pId: Integer): Integer;' + "`r`n`r`nimplementation"
  $t = [IO.File]::ReadAllText($tp)
  Check 'e0 the declaration was found' $t.Contains($old) ''
  Set-Text $tp ($t.Replace($old, 'function R1TitleLen(const pId: Integer): Integer; cdecl; varargs;' + "`r`n`r`nimplementation"))
  $dbE = Join-Path $WorkDir 'r1twovarargs.sqlite'
  Check 'e1 indexed' ((Invoke-Index (Join-Path $re 'R1Extend.dproj') $dbE 'e') -eq 0)
  $pe = Get-Cycles $dbE 'e' @('--plan')
  Check 'e2 refused: unsupported-directive naming R1TitleLen' `
    ($pe.Out.Contains('refused: unsupported-directive -- `R1TitleLen`: the directive `varargs` changes its procedural type') -and
     (($pe.Dump[1].refusals -split ',') -contains 'unsupported-directive')) "[$($pe.Dump[1].verdict) / $($pe.Dump[1].refusals)]"
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }