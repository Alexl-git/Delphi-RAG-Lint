<#
  run_cyclefix_untangle_catalog.ps1 -- E18 Task 4b: `cycles --plan` names its leaf units
  `<Source>.Untangle` and REUSES an existing one (DRagLint.Report.UntangleCatalog).

  (a) circular-demo copy: cycle 1's Step 3 creates `DemoSession.Untangle`, `DemoLogger.Untangle`
      and `DemoAudit.Untangle`; the word `.Contracts` appears nowhere in the plan.
  (b) tests\fixtures\cyclefix\untangle-reuse copy: the demo's 4-unit cycle plus an EXISTING
      `DemoAudit.Untangle.pas` (an unrelated enum, `uses System.SysUtils`, used by no unit of the
      cycle). Step 3 creates only the two other units; Step 4 inserts `TDemoAuditKind` into the
      existing unit after its last interface declaration (line 15) and merges `System.Classes`
      into its uses clause; nothing registers it in the .dpr / .dproj again. The follower
      (tools\follow-cycle-plan.ps1) applies the plan (exit 0); the tree compiles (dcc, when RAD
      Studio is installed); re-indexed, `cycles` prints the plan's predicted output.
  (c) POSITIVE CONTROL: the same fixture with `DemoAudit.Untangle` made to use `DemoLogger` (a
      unit of the cycle) is no longer a leaf: the plan creates `DemoAudit.Untangle2` and prints
      why. Without this, (b) could pass on a catalog that reuses ANY unit with the right name.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-untangle-catalog-$PID"
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
$Exe    = (Resolve-Path $Exe).Path
$Repo   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$RsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$Ascii  = [Text.Encoding]::ASCII

# Copies the .pas / .dpr / .dproj files of pFrom into a new dir pTo.
function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}

# Indexes pDproj into pDb; returns the exit code.
function Invoke-Index([string]$Dproj, [string]$Db, [string]$Tag) {
  & $Exe index --project $Dproj --db $Db *> (Join-Path $WorkDir "index-$Tag.log")
  return $LASTEXITCODE
}

# Runs `cycles` (with pExtra) on pDb; stdout only, saved to plan-<tag>.out.
function Get-Cycles([string]$Db, [string]$Tag, [string[]]$Extra) {
  $o = Join-Path $WorkDir "cycles-$Tag.out"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList (@('cycles', '--db', ('"' + $Db + '"')) + $Extra + $(if ($Extra -contains '--plan') { @('--library-db', 'none') } else { @() })) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "cycles-$Tag.err")
  return @{ Exit = $p.ExitCode; Out = [IO.File]::ReadAllText($o); File = $o }
}

# The lines of cycle pNo's block in a plan.
function Get-CycleBlock([string]$Plan, [int]$No) {
  $all = @($Plan -split "`r?`n"); $out = @(); $in = $false
  foreach ($l in $all) {
    if ($l -match '^## Cycle (\d+):') { $in = ([int]$Matches[1] -eq $No); continue }
    if ($in) { $out += $l }
  }
  return ,$out
}

# The unit names Step 3 of a cycle block creates (`#### `<unit>` -> `<path>``).
function Get-NewUnits([string[]]$Blk) {
  $out = @(); $in = $false
  foreach ($l in $Blk) {
    if ($l -match '^### Step 3') { $in = $true; continue }
    if ($l -match '^### ') { $in = $false }
    if ($in -and $l -match '^#### `([^`]+)` -> `') { $out += $Matches[1] }
  }
  return ,$out
}

# The edits Step 4 lists for one file: the lines from its `#### `<name>`` heading to the next heading.
function Get-FileEdits([string[]]$Blk, [string]$FileName) {
  $out = @(); $in = $false
  foreach ($l in $Blk) {
    if ($l -match '^####? ') { $in = $l.StartsWith('#### `' + $FileName + '`  ('); continue }
    if ($in) { $out += $l }
  }
  return ,$out
}

# The group lines of a `cycles` text report, each with its members sorted, as one string.
function Get-Groups([string[]]$Lines) {
  $g = foreach ($l in $Lines) {
    if ($l -match '^\s*\[(\d+) units\] (.+?)   (\(.+\))\s*$') {
      $m = @($Matches[2] -split ' <-> ' | Sort-Object) -join ','
      "[$($Matches[1])] $m $($Matches[3])"
    } elseif ($l -match '^\d+ circular unit group\(s\) found:$|^No circular unit dependencies found\.$') { $l }
  }
  return (@($g | Sort-Object) -join ' | ')
}

# Compiles pDpr in its own folder with dcc64; returns @{ Ran; Ok; Log }.
function Invoke-Compile([string]$Dir, [string]$Dpr) {
  if (-not (Test-Path $RsVars)) { return @{ Ran = $false; Ok = $true; Log = '' } }
  $bat = Join-Path $WorkDir ('dcc-' + (Split-Path $Dir -Leaf) + '.bat')
  $log = "$bat.log"
  $lines = @('@echo off', ('call "{0}" >NUL' -f $RsVars), ('cd /d "{0}"' -f $Dir),
    ('dcc64 -Q -B -NU"{0}" -E"{0}" {1}' -f $Dir, $Dpr), 'echo DCC_EXIT=%ERRORLEVEL%')
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), $Ascii)
  Start-Process -FilePath $bat -Wait -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError "$log.err"
  $t = [IO.File]::ReadAllText($log)
  return @{ Ran = $true; Ok = ($t -match 'DCC_EXIT=0') -and ($t -notmatch '(?m)^\S+\(\d+\) (Error|Fatal)'); Log = $t }
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  if (-not (Test-Path $RsVars)) { Write-Host '  SKIP: RAD Studio not installed -- the compile steps are skipped' -ForegroundColor Yellow }

  # --- (a) the demo -------------------------------------------------------------------------
  Write-Host '== (a) circular-demo: .Untangle names' -ForegroundColor Cyan
  $demo = Join-Path $WorkDir 'circular-demo'
  Copy-Tree (Join-Path $Repo 'circular-demo') $demo
  $dbA = Join-Path $WorkDir 'demo.sqlite'
  Check 'a0 demo indexed' ((Invoke-Index (Join-Path $demo 'CircularDemo.dproj') $dbA 'a') -eq 0)
  $pa = Get-Cycles $dbA 'a' @('--plan')
  $newA = Get-NewUnits (Get-CycleBlock $pa.Out 1)
  Check 'a1 Step 3 creates DemoSession/DemoLogger/DemoAudit.Untangle' `
    ((($newA | Sort-Object) -join ',') -eq 'DemoAudit.Untangle,DemoLogger.Untangle,DemoSession.Untangle') ('[' + ($newA -join ',') + ']')
  Check 'a2 no `.Contracts` anywhere in the plan' (-not $pa.Out.Contains('.Contracts')) ''

  # --- (b) an existing leaf is reused ---------------------------------------------------------
  Write-Host '== (b) untangle-reuse: the existing DemoAudit.Untangle is extended' -ForegroundColor Cyan
  $fx = Join-Path $Repo 'tests\fixtures\cyclefix\untangle-reuse'
  $rb = Join-Path $WorkDir 'reuse'
  Copy-Tree $fx $rb
  $c0 = Invoke-Compile $rb 'UntangleReuse.dpr'
  Check 'b0 the fixture compiles as shipped' $c0.Ok ($c0.Log -split "`r?`n" | Select-String 'Error|Fatal' | Select-Object -First 3)
  $dbB = Join-Path $WorkDir 'reuse.sqlite'
  Check 'b1 fixture indexed' ((Invoke-Index (Join-Path $rb 'UntangleReuse.dproj') $dbB 'b') -eq 0)
  $pb = Get-Cycles $dbB 'b' @('--plan')
  $blk = Get-CycleBlock $pb.Out 1
  $newB = Get-NewUnits $blk
  Check 'b2 Step 3 creates only DemoSession.Untangle and DemoLogger.Untangle' `
    ((($newB | Sort-Object) -join ',') -eq 'DemoLogger.Untangle,DemoSession.Untangle') ('[' + ($newB -join ',') + ']')
  $leafEd = Get-FileEdits $blk 'DemoAudit.Untangle.pas'
  $leafTx = $leafEd -join "`n"
  Check 'b3 Step 4 inserts into DemoAudit.Untangle.pas after line 15 (its last interface declaration)' `
    ($leafTx -match '(?m)^E\d+\. After line 15 \(`TDemoAuditChannel = \(acFile, acConsole\);`\), insert:') $leafTx
  Check 'b4 the insert carries TDemoAuditKind' ($leafTx.Contains('  TDemoAuditKind = (akOpen, akWork, akClose);')) ''
  Check 'b5 the uses clause of DemoAudit.Untangle gains System.Classes (lexer add)' `
    ($leafTx -match '(?s)Replace line 11\. Current text:\n```pascal\n  System\.SysUtils;\n```\nNew text:\n```pascal\n  System\.SysUtils,\n  System\.Classes;\n```') $leafTx
  $prjEd  = (Get-FileEdits $blk 'UntangleReuse.dproj') -join "`n"
  Check 'b6 the .dproj registers the two new units, not the existing one' `
    ((-not $prjEd.Contains('DemoAudit.Untangle.pas')) -and $prjEd.Contains('DemoLogger.Untangle.pas') -and $prjEd.Contains('DemoSession.Untangle.pas')) $prjEd
  $fo = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $pb.File -Cycle 1 -Root $rb 2>&1 | Out-String
  $rcF = $LASTEXITCODE
  Check 'b7 the follower applies cycle 1 (exit 0)' ($rcF -eq 0) ('exit=' + $rcF + ' ' + ($fo.Trim() -replace "`r?`n", ' | '))
  $leafNow = [IO.File]::ReadAllText((Join-Path $rb 'DemoAudit.Untangle.pas'))
  Check 'b8 DemoAudit.Untangle.pas holds both enums, no DemoAudit.Untangle2.pas' `
    ($leafNow.Contains('TDemoAuditKind = (akOpen') -and $leafNow.Contains('TDemoAuditChannel') -and -not (Test-Path (Join-Path $rb 'DemoAudit.Untangle2.pas'))) ''
  $dprNow = [IO.File]::ReadAllText((Join-Path $rb 'UntangleReuse.dpr'))
  Check 'b8b the .dpr names DemoAudit.Untangle once, as before' `
    (([regex]::Matches($dprNow, 'DemoAudit\.Untangle in ')).Count -eq 1) ''
  $c1 = Invoke-Compile $rb 'UntangleReuse.dpr'
  Check 'b9 the followed tree compiles' $c1.Ok ($c1.Log -split "`r?`n" | Select-String 'Error|Fatal' | Select-Object -First 3)
  Check 'b10 re-indexed' ((Invoke-Index (Join-Path $rb 'UntangleReuse.dproj') $dbB 'b2') -eq 0)
  $after = Get-Cycles $dbB 'b-after' @()
  $pred = @(); $inPred = $false
  foreach ($l in $blk) {
    if ($l -match 'It must print exactly:') { $inPred = $true; continue }
    if ($inPred -and $l -eq '```text') { continue }
    if ($inPred -and $l -eq '```') { break }
    if ($inPred) { $pred += $l }
  }
  $gP = Get-Groups $pred; $gA = Get-Groups @($after.Out -split "`r?`n")
  Check 'b11 `cycles` prints the predicted implementation-only result' (($gP -ne '') -and ($gP -eq $gA) -and ($gA -match 'implementation-only')) ("predicted [$gP] actual [$gA]")

  # --- (c) positive control: a stem that uses the cycle is no leaf -----------------------------
  Write-Host '== (c) positive control: DemoAudit.Untangle uses DemoLogger' -ForegroundColor Cyan
  $rc = Join-Path $WorkDir 'collide'
  Copy-Tree $fx $rc
  $lp = Join-Path $rc 'DemoAudit.Untangle.pas'
  $t = [IO.File]::ReadAllText($lp).Replace("implementation`r`n", "implementation`r`n`r`nuses`r`n  DemoLogger;`r`n")
  [IO.File]::WriteAllText($lp, $t, $Ascii)
  $dbC = Join-Path $WorkDir 'collide.sqlite'
  Check 'c0 control fixture indexed' ((Invoke-Index (Join-Path $rc 'UntangleReuse.dproj') $dbC 'c') -eq 0)
  $pc = Get-Cycles $dbC 'c' @('--plan')
  $blkC = Get-CycleBlock $pc.Out 1
  $newC = Get-NewUnits $blkC
  Check 'c1 Step 3 creates DemoAudit.Untangle2 (and the other two)' `
    ((($newC | Sort-Object) -join ',') -eq 'DemoAudit.Untangle2,DemoLogger.Untangle,DemoSession.Untangle') ('[' + ($newC -join ',') + ']')
  Check 'c2 the plan says why' `
    (($blkC -join "`n").Contains('existing DemoAudit.Untangle uses DemoLogger, a unit of this cycle -- creating DemoAudit.Untangle2')) ''
  Check 'c3 nothing is inserted into the colliding unit' ((Get-FileEdits $blkC 'DemoAudit.Untangle.pas').Count -eq 0) ''

  # --- (d) T17b D2: the source already uses its leaf (a second pass after Part A) --------------
  Write-Host '== (d) DemoAudit uses DemoAudit.Untangle: no self-use is planned' -ForegroundColor Cyan
  $rd = Join-Path $WorkDir 'selfuse'
  Copy-Tree $fx $rd
  $ap = Join-Path $rd 'DemoAudit.pas'
  $t = [IO.File]::ReadAllText($ap).Replace("  System.SysUtils,`r`n  System.Classes;`r`n`r`ntype", "  System.SysUtils,`r`n  System.Classes,`r`n  DemoAudit.Untangle;`r`n`r`ntype")
  [IO.File]::WriteAllText($ap, $t, $Ascii)
  Check 'd0 DemoAudit now uses DemoAudit.Untangle in its interface' $t.Contains("  DemoAudit.Untangle;`r`n`r`ntype") ''
  $dbD = Join-Path $WorkDir 'selfuse.sqlite'
  Check 'd1 fixture indexed' ((Invoke-Index (Join-Path $rd 'UntangleReuse.dproj') $dbD 'd') -eq 0)
  $pd = Get-Cycles $dbD 'd' @('--plan')
  $blkD = Get-CycleBlock $pd.Out 1
  $leafD = (Get-FileEdits $blkD 'DemoAudit.Untangle.pas') -join "`n"
  Check 'd2 the existing leaf is still extended (positive control: the edits are there)' $leafD.Contains('  TDemoAuditKind = (akOpen, akWork, akClose);') $leafD
  Check 'd3 no edit of DemoAudit.Untangle.pas adds DemoAudit.Untangle to its own uses' `
    (-not ($leafD -match '(?m)^\s*DemoAudit\.Untangle[;,]')) $leafD
  $fo = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $pd.File -Cycle 1 -Root $rd 2>&1 | Out-String
  Check 'd4 the follower applies cycle 1 (exit 0)' ($LASTEXITCODE -eq 0) ($fo.Trim() -replace "`r?`n", ' | ')
  $c2 = Invoke-Compile $rd 'UntangleReuse.dpr'
  Check 'd5 the followed tree compiles (no F2092 self-use)' $c2.Ok ($c2.Log -split "`r?`n" | Select-String 'Error|Fatal' | Select-Object -First 3)

  # --- (e) the Task-17 Part B shape: an IMPLEMENTATION cycle cut by moving a const into the ----
  #         existing leaf its source already uses (tests\fixtures\cyclefix\partbselfuse) ------------
  Write-Host '== (e) Part B moves CSuMaxVia into SuFacts.Untangle, which SuFacts already uses' -ForegroundColor Cyan
  $re = Join-Path $WorkDir 'partbselfuse'
  Copy-Tree (Join-Path $Repo 'tests\fixtures\cyclefix\partbselfuse') $re
  $dbE = Join-Path $WorkDir 'partbselfuse.sqlite'
  Check 'e1 fixture indexed' ((Invoke-Index (Join-Path $re 'PartBSelfUse.dproj') $dbE 'e') -eq 0)
  $pe = Get-Cycles $dbE 'e' @('--plan')
  $blkE = Get-CycleBlock $pe.Out 1
  Check 'e2 the cycle is implementation-only (Part B)' (($blkE -join "`n").Contains('**implementation-only**')) ''
  $leafE = (Get-FileEdits $blkE 'SuFacts.Untangle.pas') -join "`n"
  Check 'e3 the existing leaf receives CSuMaxVia (positive control: the edits are there)' $leafE.Contains('  CSuMaxVia = 3;') $leafE
  Check 'e4 no edit of SuFacts.Untangle.pas adds SuFacts.Untangle to its own uses' `
    (-not ($leafE -match '(?m)^\s*SuFacts\.Untangle[;,]')) $leafE
  $fe = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $pe.File -Cycle 1 -Root $re 2>&1 | Out-String
  Check 'e5 the follower applies cycle 1 (exit 0)' ($LASTEXITCODE -eq 0) ($fe.Trim() -replace "`r?`n", ' | ')
  $c3 = Invoke-Compile $re 'PartBSelfUse.dpr'
  Check 'e6 the followed tree compiles (no F2092 self-use)' $c3.Ok ($c3.Log -split "`r?`n" | Select-String 'Error|Fatal' | Select-Object -First 3)
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
