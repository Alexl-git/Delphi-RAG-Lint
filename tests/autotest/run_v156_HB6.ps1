<#
  run_v156_HB6.ps1 -- 1.56 lane HB6: the in-force question of `happens-before` and its three presets
  use-after-free, finalization, lock-held-when.

  Indexes the folders of tests\fixtures\v156-hb6 into scratch DBs and asks `happens-before --json`.

  POSITIVE CONTROL: every family is a set of twins that differ by ONE construct and must give
  DIFFERENT verdicts, so an engine that answers one verdict for everything fails:
    U  --preset use-after-free --a <variable>     (A = free:X in force, B = use:X)
         U1 GA  Free; use                               YES  in-force
         U2 GB  Free; GB := Create; use                 NO   b-never-after-a (reassigned-first)
         U3 GC  if .. then Free; use                    MAY  b-may-run-after-a
         U4 GD  Free; RenewD; use  (callee re-assigns)  MAY
         U5 GE  never freed                             NO   a-never-happens
         U6 TBox.FItems  FItems.Free; FItems.Add        YES
         U7 TBox.FOther  pBox.FOther.Free; FOther.Add   MAY  (the free is on another object)
         U11 GF  while .. do begin use; Free end        MAY  (the back edge)
         U12 GG  Free; try GG := ..; use except use end MAY  (an undo inside try..except: refused)
    L  --preset lock-held-when --a <lock> --b <event>   (A = held:L in force at every site of B)
         L1 Enter; try write finally Leave              YES  in-force
         L2 Enter; Leave; write                         MAY
         L3 if .. then Enter; write                     MAY
         L4 lock never entered                          NO   a-never-happens
         L5 Enter; Drop5 (callee leaves); write         MAY
    F  --preset finalization --a <unit variable>        (A = final-free:X, B = use:X)
         F1 GLog    used by normal code only            NO   b-never-after-a (finalization-order)
         F2 GCache  used in a destructor                MAY
         F3 GLate   used by a later finalization (call) MAY
         F4 GPlain  not freed by a finalization         NO   a-never-happens
         F5 GHelper freed by a routine, not the section MAY  a-sites-incomplete
         F6 GOrder1 use; free   in the section          NO
         F7 GOrder2 free; use   in the section          MAY
    X  usage: a preset without --a, an event in place of the variable -> exit 2
  -BaseExe <engine at the HB5 commit>: asserts THAT engine does not know the presets (the RED).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '', [string]$BaseExe = '', [string]$WorkDir = '', [switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_v156_HB6: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
if (-not (Test-Path $Exe)) { Write-Host "run_v156_HB6: no engine at $Exe" -ForegroundColor Red; exit 2 }
$fxSrc = Join-Path $repo 'tests\fixtures\v156-hb6'
if ($WorkDir -eq '') { $WorkDir = Join-Path $env:TEMP ('dl-v156-hb6-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)) }
New-Item -ItemType Directory -Force $WorkDir | Out-Null

$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name  $Detail" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}

function Lane-Index([string]$Engine, [string]$Folder) {
  $fx = Join-Path $WorkDir "fx-$Folder"
  New-Item -ItemType Directory -Force $fx | Out-Null
  Copy-Item (Join-Path $fxSrc "$Folder\*") $fx -Force
  $db = Join-Path $WorkDir "hb6-$Folder.sqlite"
  $log = Join-Path $WorkDir "index-$Folder.log"
  & { $ErrorActionPreference = 'Continue'; & $Engine index $fx --db $db *> $log }
  return @{ rc = $LASTEXITCODE; db = $db; fx = $fx }
}

# happens-before -> rc, stdout lines, stderr text, parsed JSON (or $null)
function Lane-Ask([string]$Engine, [string[]]$VerbArgs) {
  $errFile = Join-Path $WorkDir 'stderr.txt'
  $raw = & { $ErrorActionPreference = 'Continue'; & $Engine happens-before @VerbArgs 2>$errFile }
  $rc = $LASTEXITCODE
  $j = $null
  if ($raw) { try { $j = (($raw -join "`n") | ConvertFrom-Json | ForEach-Object { $_ }) } catch { $j = $null } }
  $err = if (Test-Path $errFile) { [IO.File]::ReadAllText($errFile) } else { '' }
  return [pscustomobject]@{ rc = $rc; out = @($raw); err = $err; j = $j }
}

# One verdict check: verdict, exit code, the in-force question, and (optional) reason / method code.
function Check-Verdict([string]$Name, $Ans, [string]$Verdict, [string]$Reason = '', [string]$Method = '') {
  $v = if ($Ans.j) { [string]$Ans.j.verdict } else { '(no JSON)' }
  $wantRc = if ($Verdict -eq 'YES') { 0 } else { 1 }
  $reasons = @(if ($Ans.j) { $Ans.j.reasons } else { @() })
  $methods = @(if ($Ans.j) { $Ans.j.methods } else { @() })
  $q = if ($Ans.j) { [string]$Ans.j.question } else { '' }
  $ok = ($v -eq $Verdict) -and ($Ans.rc -eq $wantRc) -and ($q -eq 'in-force')
  if ($Reason -ne '') { $ok = $ok -and ($reasons -contains $Reason) }
  if ($Method -ne '') { $ok = $ok -and ($methods -contains $Method) }
  $errLine = (($Ans.err -split "`n")[0]).Trim()
  Check $Name $ok "verdict=$v rc=$($Ans.rc) question=$q reasons=[$($reasons -join ',')] methods=[$($methods -join ',')] $errLine"
}

Write-Host "run_v156_HB6: engine $Exe" -ForegroundColor Cyan
$uaf = Lane-Index $Exe 'uaf'
$lock = Lane-Index $Exe 'lock'
$fin = Lane-Index $Exe 'fin'
Check 'V1 the three fixture folders index' (($uaf.rc -eq 0) -and ($lock.rc -eq 0) -and ($fin.rc -eq 0)) "rc=$($uaf.rc),$($lock.rc),$($fin.rc)"

Write-Host '-- U: use-after-free' -ForegroundColor Cyan
function Ask-Uaf([string]$Var) { Lane-Ask $Exe @('--preset', 'use-after-free', '--a', $Var, '--db', $uaf.db, '--json') }
$u1 = Ask-Uaf 'uUaf.GA'
Check-Verdict 'U1 Free; use -> YES' $u1 'YES' '' 'in-force'
Check-Verdict 'U2 Free; re-assign; use -> NO' (Ask-Uaf 'uUaf.GB') 'NO' 'b-never-after-a' 'reassigned-first'
Check-Verdict 'U3 conditional Free; use -> MAY' (Ask-Uaf 'uUaf.GC') 'MAY' 'b-may-run-after-a'
Check-Verdict 'U4 Free; callee re-assigns; use -> MAY' (Ask-Uaf 'uUaf.GD') 'MAY' 'b-may-run-after-a'
Check-Verdict 'U5 never freed -> NO' (Ask-Uaf 'uUaf.GE') 'NO' 'a-never-happens'
$u6 = Ask-Uaf 'uUaf.TBox.FItems'
Check-Verdict 'U6 field: FItems.Free; FItems.Add -> YES' $u6 'YES' '' 'in-force'
Check 'U6b a field answer carries the limit instance-insensitive' ($u6.j -and (@($u6.j.limits) -contains 'instance-insensitive')) ''
Check-Verdict 'U7 field freed on ANOTHER object; use on Self -> MAY' (Ask-Uaf 'uUaf.TBox.FOther') 'MAY' 'b-may-run-after-a'
Check 'U8 the events are free:<var> and use:<var>, one site each for GA' ($u1.j -and ($u1.j.a.event -eq 'free:uUaf.GA') -and
  ($u1.j.b.event -eq 'use:uUaf.GA') -and (@($u1.j.a.sites).Count -eq 1) -and (@($u1.j.b.sites).Count -eq 1)) ''
Check 'U9 a use-after-free answer carries the limit aliases-not-followed' ($u1.j -and (@($u1.j.limits) -contains 'aliases-not-followed')) ''
$u1t = Lane-Ask $Exe @('--preset', 'use-after-free', '--a', 'uUaf.GA', '--db', $uaf.db)
$u1text = $u1t.out -join "`n"
Check 'U10 text output: verdict line and the judged use' (($u1text -match 'verdict\s+YES') -and ($u1text -match 'B\s+uUaf\.pas:\d+:\d+\s+in uUaf\.UafAfter\s+in-force')) ''

Check-Verdict 'U11 use; Free in a loop (the back edge) -> MAY, never NO' (Ask-Uaf 'uUaf.GF') 'MAY' 'b-may-run-after-a'
$u12 = Ask-Uaf 'uUaf.GG'
Check-Verdict 'U12 Free; try re-assign; use except use -> MAY (an undo inside try..except is refused)' $u12 'MAY' 'b-may-run-after-a'
$u12p = @(if ($u12.j) { $u12.j.judged | Where-Object { $_.proven } })
Check 'U12b only the use after the re-assignment is proven (reassigned-first); the use in the handler stays open' (($u12p.Count -eq 1) -and
  ($u12p[0].method -eq 'reassigned-first') -and (@($u12.j.judged).Count -eq 2)) "proven=$($u12p.Count)"

Write-Host '-- L: lock-held-when' -ForegroundColor Cyan
function Ask-Lock([string]$N) {
  Lane-Ask $Exe @('--preset', 'lock-held-when', '--a', "uLock.TAcct.FLock$N", '--b', "write:uLock.TAcct.FBal$N", '--db', $lock.db, '--json')
}
Check-Verdict 'L1 Enter; try write finally Leave -> YES' (Ask-Lock '1') 'YES' '' 'in-force'
Check-Verdict 'L2 Enter; Leave; write -> MAY' (Ask-Lock '2') 'MAY' 'b-may-run-after-a'
Check-Verdict 'L3 conditional Enter; write -> MAY' (Ask-Lock '3') 'MAY' 'b-may-run-after-a'
Check-Verdict 'L4 lock never entered -> NO' (Ask-Lock '4') 'NO' 'a-never-happens'
Check-Verdict 'L5 Enter; callee leaves; write -> MAY' (Ask-Lock '5') 'MAY' 'b-may-run-after-a'

Write-Host '-- F: finalization' -ForegroundColor Cyan
function Ask-Fin([string]$Var) { Lane-Ask $Exe @('--preset', 'finalization', '--a', "uFinRes.$Var", '--db', $fin.db, '--json') }
Check-Verdict 'F1 used by normal code only -> NO' (Ask-Fin 'GLog') 'NO' 'b-never-after-a' 'finalization-order'
Check-Verdict 'F2 used in a destructor -> MAY' (Ask-Fin 'GCache') 'MAY' 'b-may-run-after-a'
Check-Verdict 'F3 used by a routine another finalization calls -> MAY' (Ask-Fin 'GLate') 'MAY' 'b-may-run-after-a'
Check-Verdict 'F4 not freed by a finalization -> NO' (Ask-Fin 'GPlain') 'NO' 'a-never-happens'
Check-Verdict 'F5 freed by a routine the section calls -> MAY' (Ask-Fin 'GHelper') 'MAY' 'a-sites-incomplete'
Check-Verdict 'F6 use; free in the section -> NO' (Ask-Fin 'GOrder1') 'NO' 'b-never-after-a' 'finalization-order'
Check-Verdict 'F7 free; use in the section -> MAY' (Ask-Fin 'GOrder2') 'MAY' 'b-may-run-after-a'

Write-Host '-- X: usage' -ForegroundColor Cyan
$x1 = Lane-Ask $Exe @('--preset', 'use-after-free', '--db', $uaf.db)
Check 'X1 use-after-free without --a -> exit 2' (($x1.rc -eq 2) -and ($x1.err -match 'use-after-free needs --a')) "rc=$($x1.rc)"
$x2 = Lane-Ask $Exe @('--preset', 'finalization', '--a', 'write:uFinRes.GLog', '--db', $fin.db)
Check 'X2 an event in place of the variable -> exit 2' (($x2.rc -eq 2) -and ($x2.err -match 'variable')) "rc=$($x2.rc)"
$x3 = Lane-Ask $Exe @('--preset', 'lock-held-when', '--a', 'uLock.TAcct.FLock1', '--db', $lock.db)
Check 'X3 lock-held-when without --b -> exit 2' (($x3.rc -eq 2) -and ($x3.err -match '--b')) "rc=$($x3.rc)"
$x4 = Lane-Ask $Exe @('--preset', 'finalization', '--a', 'uUaf.TBox.FItems', '--db', $uaf.db)
Check 'X4 finalization of an instance field -> exit 2' (($x4.rc -eq 2) -and ($x4.err -match 'unit variable')) "rc=$($x4.rc)"
$x5 = Lane-Ask $Exe @('--a', 'write:uUaf.GA', '--b', 'read:uUaf.GA', '--db', $uaf.db, '--json')
Check 'X5 a plain --a / --b question stays the happens-before question (no "question" key)' ($x5.j -and
  (-not $x5.j.PSObject.Properties['question']) -and ($x5.j.verdict -eq 'YES')) "verdict=$(if ($x5.j) { $x5.j.verdict })"

if ($BaseExe -ne '') {
  Write-Host '-- BASE: the HB5 engine' -ForegroundColor Cyan
  $b1 = Lane-Ask $BaseExe @('--preset', 'use-after-free', '--a', 'uUaf.GA', '--db', $uaf.db, '--json')
  Check 'BASE the HB5 engine does not know the preset' (($b1.rc -eq 2) -and ($b1.err -match 'unknown preset|names both events')) "rc=$($b1.rc)"
}

Write-Host ("run_v156_HB6: {0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
if (-not $KeepScratch) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
exit $(if ($script:fail -eq 0) { 0 } else { 1 })
