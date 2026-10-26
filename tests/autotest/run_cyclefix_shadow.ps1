<#
  run_cyclefix_shadow.ps1 -- E18 Task 9: `cycles --fix` stages a SHADOW TREE.

  For each of the demo's three kinds of group (default scan = Part A, --unit demogageport = R2,
  --unit demoblueprint = R1) the runner
    1. copies circular-demo, indexes it, runs `cycles --fix --shadow-out <dir> --format json`
       (dry run: exit 0, the project copy is byte-identical before and after);
    2. takes `cycles --plan` of the same copy, applies the chosen cycle with the ORACLE
       tools\follow-cycle-plan.ps1 to ANOTHER copy;
    3. asserts the shadow tree equals, file by file, what the oracle produced: the same set of
       files (every edited file, every new unit) and byte-identical content.
  Controls: (c1) the file comparison is not vacuous -- one flipped byte in a shadow copy is
  reported; (c2) the shadow holds the new leaf units; (c3) with no --shadow-out the default dir
  C:\TEMP\draglint_cyclefix_<pid>\ is announced and exists; (c4) a successful run deletes it and says so on the
  Shadow line; final review F5 (amended; needs RAD Studio, else SKIP): (c7) a run whose message cites a scratch
  file keeps it and names it on stderr; (c7b) a log never created is never cited; (c8) a refused dry run keeps nothing.
  The platform library is never opened in place: R2 uses a scratch copy (SKIPped without one).
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [switch]$KeepScratch,
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-shadow-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite'
)
# E18 T13: removes this run's scratch (WorkDir) however the run ends; kept only on failure when
# -KeepScratch is passed (the path is printed).
function Remove-Scratch {
  if ($script:Failed -and $KeepScratch) { Write-Host "scratch kept: $WorkDir" -ForegroundColor Yellow; return }
  Set-Location -LiteralPath $env:TEMP
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
trap { $script:Failed = $true; Remove-Scratch; break }

$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Demo = Join-Path $Repo 'circular-demo'

function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}
function Get-LibStamp {
  return (@(Get-ChildItem 'C:\Projects\.drag-lint' -Filter 'library-*.sqlite' -ErrorAction SilentlyContinue |
    Sort-Object Name | ForEach-Object { '{0}={1}@{2:o}' -f $_.Name, $_.Length, $_.LastWriteTimeUtc }) -join ' ')
}
function Get-TreeHash([string]$Dir) {
  return ((Get-ChildItem $Dir -File -Recurse | Sort-Object FullName | ForEach-Object {
    '{0}={1}' -f $_.Name, (Get-FileHash $_.FullName -Algorithm SHA256).Hash }) -join ';')
}
# relative path (lower case) -> SHA-256, for every file under Dir
function Get-Map([string]$Dir) {
  $m = @{}
  $base = (Resolve-Path $Dir).Path.TrimEnd('\') + '\'
  Get-ChildItem $Dir -File -Recurse | ForEach-Object {
    $m[$_.FullName.Substring($base.Length).ToLowerInvariant()] = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
  }
  return $m
}
# the files the oracle changed or created: those whose hash differs from the pristine demo
function Get-Delta([hashtable]$Pristine, [hashtable]$After) {
  $d = @{}
  foreach ($k in $After.Keys) { if (-not $Pristine.ContainsKey($k) -or $Pristine[$k] -ne $After[$k]) { $d[$k] = $After[$k] } }
  return $d
}
# Empty string when equal, else a description of the differences.
function Compare-Maps([hashtable]$Want, [hashtable]$Got) {
  $bad = @()
  foreach ($k in $Want.Keys) {
    if (-not $Got.ContainsKey($k)) { $bad += "missing in shadow: $k" }
    elseif ($Got[$k] -ne $Want[$k]) { $bad += "differs: $k" }
  }
  foreach ($k in $Got.Keys) { if (-not $Want.ContainsKey($k)) { $bad += "unexpected in shadow: $k" } }
  return ($bad -join '; ')
}

function Run-Case([string]$Tag, [string[]]$Select, [string]$LibArg) {
  Write-Host "== $Tag" -ForegroundColor Cyan
  $proj = Join-Path $WorkDir "$Tag-proj"
  $orc  = Join-Path $WorkDir "$Tag-oracle"
  $shadow = Join-Path $WorkDir "$Tag-shadow"
  Copy-Tree $Demo $proj
  Copy-Tree $Demo $orc
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project (Join-Path $proj 'CircularDemo.dproj') --db $db *> (Join-Path $WorkDir "$Tag-index.log")
  Check "${Tag}: demo indexed" ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  $hashBefore = Get-TreeHash $proj
  $out = (& $Exe cycles --fix --project (Join-Path $proj 'CircularDemo.dproj') --db $db @Select `
    --no-compile --library-db $LibArg --shadow-out $shadow --format json 2>$null | Out-String)
  $code = $LASTEXITCODE
  $j = try { $out | ConvertFrom-Json } catch { $null }
  Check "${Tag}: dry run exit 0, mechanical" ($code -eq 0 -and $j -and $j.cycles[0].verdict -eq 'mechanical') "exit=$code $out"
  Check "${Tag}: the project copy is byte-identical after the dry run" ((Get-TreeHash $proj) -eq $hashBefore) ''
  Check "${Tag}: shadow dir exists" (Test-Path $shadow) $shadow
  if (-not $j -or -not $j.cycles) { return $null }
  $n = [int]$j.cycles[0].n
  # the oracle: the plan text of the same copy, applied to another copy
  $planFile = Join-Path $WorkDir "$Tag-plan.txt"
  & $Exe cycles --db $db --edges --causes --plan --format text --library-db $LibArg 2>$null | Out-File $planFile -Encoding ascii
  $fo = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $planFile -Cycle $n -Root $orc 2>&1 | Out-String
  Check "${Tag}: oracle applied cycle $n (exit 0)" ($LASTEXITCODE -eq 0) ($fo.Trim() -replace "`r?`n", ' | ')
  $want = Get-Delta $pristine (Get-Map $orc)
  $got  = if (Test-Path $shadow) { Get-Map $shadow } else { @{} }
  Check "${Tag}: the oracle changed something (non-vacuous)" ($want.Count -gt 0) ''
  $diff = Compare-Maps $want $got
  Check "${Tag}: shadow == oracle, file by file, byte-identical ($($want.Count) file(s))" ($diff -eq '') $diff
  return @{ Shadow = $shadow; Want = $want; Got = $got }
}

$stampBefore = Get-LibStamp
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$haveLib = Test-Path $LibraryDb
$Lib = Join-Path $WorkDir 'library-copy.sqlite'
if ($haveLib) { Copy-Item $LibraryDb $Lib -Force }
$pristine = Get-Map $Demo
Push-Location $WorkDir
try {
  $a = Run-Case 'partA' @() 'none'
  if ($a) {
    Check 'c2: Part A shadow holds the 3 new leaf units' (@($a.Got.Keys | Where-Object { $_ -like '*.untangle.pas' }).Count -eq 3) (($a.Got.Keys | Sort-Object) -join ',')
    # c1: negative control of the comparison
    $any = (Get-ChildItem $a.Shadow -Filter *.pas | Select-Object -First 1)
    $bytes = [IO.File]::ReadAllBytes($any.FullName)
    $bytes[0] = $bytes[0] -bxor 1
    $tampered = Join-Path $WorkDir 'tampered'
    New-Item -ItemType Directory -Force $tampered | Out-Null
    Get-ChildItem $a.Shadow -File | ForEach-Object { Copy-Item $_.FullName $tampered }
    [IO.File]::WriteAllBytes((Join-Path $tampered $any.Name), $bytes)
    Check 'c1: CONTROL one flipped byte in a shadow file is reported' ((Compare-Maps $a.Want (Get-Map $tampered)) -match 'differs:') ''
  }

  if ($haveLib) {
    $null = Run-Case 'r2' @('--unit', 'demogageport') $Lib
  } else { Write-Host '  SKIP r2: no platform library DB on disk' -ForegroundColor Yellow }
  $null = Run-Case 'r1' @('--unit', 'demoblueprint') 'none'

  Write-Host '== c3: default shadow dir' -ForegroundColor Cyan
  $dproj = Join-Path $WorkDir 'dflt'
  Copy-Tree $Demo $dproj
  $ddb = Join-Path $WorkDir 'dflt.sqlite'
  & $Exe index --project (Join-Path $dproj 'CircularDemo.dproj') --db $ddb *> (Join-Path $WorkDir 'dflt-index.log')
  # the default scratch is deleted at the end of the run (E18 T13 fix round); this check inspects it, so it asks to keep it
  $env:DRAGLINT_CYCLEFIX_KEEP_SCRATCH = '1'
  try {
    $txt = (& $Exe cycles --fix --project (Join-Path $dproj 'CircularDemo.dproj') --db $ddb --no-compile --library-db none 2>$null | Out-String)
  } finally { $env:DRAGLINT_CYCLEFIX_KEEP_SCRATCH = $null }
  $m = [regex]::Match($txt, '(?m)^Shadow tree: (\S+)')
  Check 'c3: text output announces "Shadow tree: <product root>\draglint_cyclefix_<pid>"' ($m.Success -and $m.Groups[1].Value -match '^C:\\TEMP\\draglint_cyclefix_\d+\\?$') $txt
  Check 'c3: that directory exists and holds files' ($m.Success -and (Test-Path $m.Groups[1].Value) -and (@(Get-ChildItem $m.Groups[1].Value -Recurse -File).Count -gt 0)) ''
  if ($m.Success -and (Test-Path $m.Groups[1].Value)) { [IO.Directory]::Delete($m.Groups[1].Value, $true) }
  # c4: without the seam the product deletes the default shadow it created; a --shadow-out dir is never deleted
  $txt2 = (& $Exe cycles --fix --project (Join-Path $dproj 'CircularDemo.dproj') --db $ddb --no-compile --library-db none 2>$null | Out-String)
  $m2 = [regex]::Match($txt2, '(?m)^Shadow tree: (\S+)')
  Check 'c4: the run announced a default shadow dir (SANITY) and it is gone after the run' `
    ($m2.Success -and $m2.Groups[1].Value -match '^C:\\TEMP\\draglint_cyclefix_\d+\\?$' -and -not (Test-Path $m2.Groups[1].Value) -and -not (Test-Path ($m2.Groups[1].Value.TrimEnd('\') + '_build'))) $txt2
  if ($m2.Success -and (Test-Path $m2.Groups[1].Value)) { [IO.Directory]::Delete($m2.Groups[1].Value, $true) }
  # c5: a leftover dir with the would-be name (an earlier process with this pid) is never reused and never deleted
  # the planted dirs must sit where the PRODUCT looks (its fixed default root, CycleFix.pas DefaultShadowDir),
  # so they cannot live in this run's WorkDir; their names are per run (a GUID through $fake)
  $ProductRoot = 'C:\TEMP'
  $fake = 'planted' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
  $plShadow = Join-Path $ProductRoot "draglint_cyclefix_$fake"; $plBuild = Join-Path $ProductRoot "draglint_cyclefix_${fake}_build"
  foreach ($pl in $plShadow, $plBuild) { New-Item -ItemType Directory -Force $pl | Out-Null; [IO.File]::WriteAllText((Join-Path $pl 'marker.txt'), 'keep me') }
  $env:DRAGLINT_TEST_SCRATCH_PID = $fake
  try {
    $txt3 = (& $Exe cycles --fix --project (Join-Path $dproj 'CircularDemo.dproj') --db $ddb --no-compile --library-db none 2>$null | Out-String)
    $code3 = $LASTEXITCODE
  } finally { $env:DRAGLINT_TEST_SCRATCH_PID = $null }
  $m3 = [regex]::Match($txt3, '(?m)^Shadow tree: (\S+)')
  Check 'c5: the run still succeeds (exit 0) and announces a DIFFERENT shadow dir than the planted name' `
    ($code3 -eq 0 -and $m3.Success -and $m3.Groups[1].Value.TrimEnd('\') -ne $plShadow -and $m3.Groups[1].Value -like (Join-Path $ProductRoot "draglint_cyclefix_${fake}_*")) $txt3
  Check 'c5: the planted dirs and their marker files survive' `
    ((Get-Content (Join-Path $plShadow 'marker.txt') -Raw) -eq 'keep me' -and (Get-Content (Join-Path $plBuild 'marker.txt') -Raw) -eq 'keep me' -and @(Get-ChildItem $plShadow -Recurse -File).Count -eq 1) ''
  Check 'c5: the dir this run created is gone' ($m3.Success -and -not (Test-Path $m3.Groups[1].Value)) ''
  foreach ($pl in $plShadow, $plBuild) { if (Test-Path $pl) { [IO.Directory]::Delete($pl, $true) } }
  # c6: a run that needs no default dir (validation error) deletes nothing either
  $fake2 = 'planted' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
  $pl2 = Join-Path $ProductRoot "draglint_cyclefix_$fake2"; New-Item -ItemType Directory -Force $pl2 | Out-Null; [IO.File]::WriteAllText((Join-Path $pl2 'marker.txt'), 'keep me')
  $env:DRAGLINT_TEST_SCRATCH_PID = $fake2
  try { $null = (& $Exe cycles --fix --db $ddb --library-db none 2>$null | Out-String); $code4 = $LASTEXITCODE } finally { $env:DRAGLINT_TEST_SCRATCH_PID = $null }
  Check 'c6: a --fix run that fails validation (no --project: exit 2) leaves the planted dir alone' ($code4 -eq 2 -and (Test-Path (Join-Path $pl2 'marker.txt'))) "exit=$code4"
  if (Test-Path $pl2) { [IO.Directory]::Delete($pl2, $true) }
  $own = Join-Path $WorkDir 'c4-own-shadow'
  $null = (& $Exe cycles --fix --project (Join-Path $dproj 'CircularDemo.dproj') --db $ddb --no-compile --library-db none --shadow-out $own 2>$null | Out-String)
  Check 'c4: POSITIVE CONTROL an explicit --shadow-out dir survives the run, with files' ((Test-Path $own) -and (@(Get-ChildItem $own -Recurse -File).Count -gt 0)) ''
  # final review F5: the Shadow line says what becomes of a default dir; a --shadow-out line has no such note
  Check 'c4: the Shadow line of a successful run says "(deleted at exit; --shadow-out keeps it)"' ($txt2 -match '(?m)^Shadow tree: \S+ \(deleted at exit; --shadow-out keeps it\)\s*$') $txt2
  # Final review F5 (amended): the default scratch is KEPT only when the run's output cites a file in it,
  # and a message cites a scratch file only when it exists. Every case below needs RAD Studio (a real build).
  $rsv = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
  # Runs `cycles --fix` on pDir's CircularDemo.dproj with a planted scratch pid; returns exit, JSON, stderr, dirs.
  function Run-Scratch([string]$Tag, [string]$Dir, [string]$Db, [hashtable]$Env = @{}) {
    $fk = $Tag + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $errf = Join-Path $WorkDir "$Tag-stderr.txt"
    $env:DRAGLINT_TEST_SCRATCH_PID = $fk
    foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
    try {
      $o = (& $Exe cycles --fix --project (Join-Path $Dir 'CircularDemo.dproj') --db $Db --cycle 1 --library-db none --format json 2>$errf | Out-String)
      $code = $LASTEXITCODE
    } finally {
      $env:DRAGLINT_TEST_SCRATCH_PID = $null
      foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $null) }
    }
    $j = try { $o | ConvertFrom-Json } catch { $null }
    return @{ Exit = $code; Json = $j; Out = $o; Err = [IO.File]::ReadAllText($errf)
              Build = (Join-Path $ProductRoot "draglint_cyclefix_${fk}_build"); Shadow = (Join-Path $ProductRoot "draglint_cyclefix_$fk") }
  }
  function Clear-Planted($r) { foreach ($d in $r.Build, $r.Shadow) { if (Test-Path $d) { [IO.Directory]::Delete($d, $true) } } }
  if (Test-Path $rsv) {
    # c7: a msbuild failure with no dcc line cites its log -> the scratch is kept, the log exists, stderr names the dir.
    # The .dproj is broken AFTER indexing (text after </Project>: an msbuild XML error, not a dcc error).
    $bp = Join-Path $WorkDir 'c7-proj'
    Copy-Tree $Demo $bp
    $bdb = Join-Path $WorkDir 'c7.sqlite'
    & $Exe index --project (Join-Path $bp 'CircularDemo.dproj') --db $bdb *> (Join-Path $WorkDir 'c7-index.log')
    [IO.File]::AppendAllText((Join-Path $bp 'CircularDemo.dproj'), "not xml`r`n")
    $r7 = Run-Scratch 'cite' $bp $bdb
    $msg7 = if ($r7.Json) { "$(@($r7.Json.baseline.errors)[0])" } else { '' }
    $cited = [regex]::Match($msg7, 'see (\S+)$').Groups[1].Value
    Check 'c7: SANITY the baseline fails without a dcc line: exit 1, a message citing a log in the run''s _build dir' `
      ($r7.Exit -eq 1 -and $msg7 -like 'msbuild failed without a dcc error line; see *' -and $cited.StartsWith($r7.Build)) "exit=$($r7.Exit) $($r7.Out)"
    Check 'c7: the cited log still exists after the run (the scratch was kept)' (($cited -ne '') -and (Test-Path -LiteralPath $cited)) "cited=$cited"
    Check 'c7: stderr names the kept scratch dir' ($r7.Err.Contains('its scratch is kept for the files it cites: ' + $r7.Build)) $r7.Err
    Clear-Planted $r7
    # c7b: a build killed before msbuild opened its log cites NO log, and then nothing is kept (1 ms seam, project under TEMP).
    $r7b = Run-Scratch 'kill' $dproj $ddb @{ DRAGLINT_CYCLEFIX_BUILD_TIMEOUT_MS = '1' }
    $msg7b = if ($r7b.Json) { "$(@($r7b.Json.baseline.errors)[0])" } else { '' }
    $cited7b = [regex]::Match($msg7b, 'see (\S+)$').Groups[1].Value
    Check 'c7b: SANITY exit 1, build-timeout' ($r7b.Exit -eq 1 -and $msg7b -like 'build-timeout:*') "exit=$($r7b.Exit) $($r7b.Out)"
    Check 'c7b: a cited log exists (its dir kept); with no citation the run leaves no scratch dir' `
      ((($cited7b -ne '') -and (Test-Path -LiteralPath $cited7b)) -or (($cited7b -eq '') -and -not (Test-Path $r7b.Build) -and -not (Test-Path $r7b.Shadow))) "msg=$msg7b"
    Clear-Planted $r7b
    # c8: an ordinary refusal (a file touched after indexing: stale-file, exit 1) builds the baseline, cites
    # no scratch file, and deletes its scratch like a success.
    $sp = Join-Path $WorkDir 'c8-proj'
    Copy-Tree $Demo $sp
    $sdb8 = Join-Path $WorkDir 'c8.sqlite'
    & $Exe index --project (Join-Path $sp 'CircularDemo.dproj') --db $sdb8 *> (Join-Path $WorkDir 'c8-index.log')
    Start-Sleep -Milliseconds 1100
    [IO.File]::AppendAllText((Join-Path $sp 'DemoLogger.pas'), "`r`n")
    $r8 = Run-Scratch 'refuse' $sp $sdb8
    Check 'c8: SANITY a refused dry run with a baseline build: exit 1, stale-file, baseline ok' `
      ($r8.Exit -eq 1 -and $r8.Json -and $r8.Json.baseline.status -eq 'ok' -and @($r8.Json.cycles[0].refusals | Where-Object { $_.kind -eq 'stale-file' }).Count -ge 1) $r8.Out
    Check 'c8: the refused run leaves no draglint_cyclefix_<pid>_* dir and prints no kept-scratch note' `
      (-not (Test-Path $r8.Build) -and -not (Test-Path $r8.Shadow) -and -not $r8.Err.Contains('scratch is kept')) "$($r8.Build) $($r8.Err)"
    Clear-Planted $r8
  } else { Write-Host '  SKIP c7/c7b/c8: no RAD Studio (rsvars.bat)' -ForegroundColor Yellow }
  # --- fix round 1 -------------------------------------------------------------------------
  # Index a fresh demo copy after Patch(proj) changed it; run `cycles --fix` with an explicit shadow dir.
  function Run-Patched([string]$Tag, [scriptblock]$Patch, [hashtable]$Env = @{}, [string[]]$Extra = @()) {
    $proj = Join-Path $WorkDir "$Tag-proj"
    $shadow = Join-Path $WorkDir "$Tag-shadow"
    Copy-Tree $Demo $proj
    & $Patch $proj
    $db = Join-Path $WorkDir "$Tag.sqlite"
    & $Exe index --project (Join-Path $proj 'CircularDemo.dproj') --db $db *> (Join-Path $WorkDir "$Tag-index.log")
    $errf = Join-Path $WorkDir "$Tag-stderr.txt"
    foreach ($k in $Env.Keys) { Set-Item "Env:$k" $Env[$k] }
    try {
      $out = (& $Exe cycles --fix --project (Join-Path $proj 'CircularDemo.dproj') --db $db --cycle 1 `
        --no-compile --library-db none --shadow-out $shadow --format json @Extra 2>$errf | Out-String)
      $code = $LASTEXITCODE
      $err = [IO.File]::ReadAllText($errf)
    } finally { foreach ($k in $Env.Keys) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue } }
    $j = try { $out | ConvertFrom-Json } catch { $null }
    $n = if (Test-Path $shadow) { @(Get-ChildItem $shadow -Recurse -File).Count } else { 0 }
    return @{ Exit = $code; Json = $j; Out = $out; Err = $err; Shadow = $shadow; ShadowFiles = $n; Proj = $proj }
  }
  function Patch-Bytes([string]$Path, [string]$From, [byte[]]$To) {
    $b = [IO.File]::ReadAllBytes($Path)
    $s = [Text.Encoding]::GetEncoding(28591).GetString($b)
    $i = $s.IndexOf($From)
    if ($i -lt 0) { throw "patch anchor not found: $From" }
    $nb = [byte[]]($b[0..($i - 1)] + $To + $b[($i + $From.Length)..($b.Length - 1)])
    [IO.File]::WriteAllBytes($Path, $nb)
  }

  Write-Host '== e1: a non-ASCII char in a line the recipe copies into a new unit (staged UTF-8 + BOM)' -ForegroundColor Cyan
  # 0xE9 (e-acute, cp1252) in the doc comment of TDemoLogLevel, which Part A moves into a new unit.
  $r = Run-Patched 'e1' { param($p) Patch-Bytes (Join-Path $p 'DemoLogger.pas') 'Severity of a log line' ([byte[]](0x53,0xE9,0x76,0xE9,0x72,0x69,0x74,0xE9)) }
  $kinds = if ($r.Json) { @($r.Json.cycles[0].refusals | ForEach-Object { $_.kind }) } else { @() }
  # W6 C7 (lane CYCC): was refused non-ascii-text; the new unit is now staged as UTF-8 with a BOM.
  Check 'e1: exit 0, mechanical (no non-ascii-text refusal)' ($r.Exit -eq 0 -and -not ($kinds -contains 'non-ascii-text')) $r.Out
  $nu = @(Get-ChildItem $r.Shadow -Recurse -File -Filter 'DemoLogger.Untangle.pas' -ErrorAction SilentlyContinue)
  $nb = if ($nu.Count -gt 0) { [IO.File]::ReadAllBytes($nu[0].FullName) } else { [byte[]]@() }
  Check 'e1: the new unit is staged with the UTF-8 BOM' ($nb.Length -gt 3 -and $nb[0] -eq 0xEF -and $nb[1] -eq 0xBB -and $nb[2] -eq 0xBF) "units=$($nu.Count)"
  Check 'e1: the copied text survives as UTF-8 (S e-acute v ...)' (([Text.Encoding]::UTF8.GetString($nb)).Contains('S' + [char]0xE9 + 'v' + [char]0xE9 + 'rit' + [char]0xE9)) ''

  Write-Host '== e2: a UTF-8 BOM file keeps its BOM and bytes outside the edits' -ForegroundColor Cyan
  $r = Run-Patched 'e2' { param($p)
    $f = Join-Path $p 'DemoLogger.pas'
    $txt = [IO.File]::ReadAllText($f).Replace('CYCLE ROLE', ('CYCLE R' + [char]0xD4 + 'LE'))
    [IO.File]::WriteAllText($f, $txt, (New-Object Text.UTF8Encoding($true))) }
  Check 'e2: exit 0, mechanical' ($r.Exit -eq 0 -and $r.Json -and $r.Json.cycles[0].verdict -eq 'mechanical') $r.Out
  $sb = Join-Path $r.Shadow 'DemoLogger.pas'
  $bytes = if (Test-Path $sb) { [IO.File]::ReadAllBytes($sb) } else { [byte[]]@() }
  Check 'e2: staged DemoLogger.pas starts with the UTF-8 BOM' ($bytes.Length -gt 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) ''
  Check 'e2: the non-ASCII char survives as UTF-8 (C3 94 not C3 83 ..)' (([Text.Encoding]::UTF8.GetString($bytes)).Contains('CYCLE R' + [char]0xD4 + 'LE')) ''

  Write-Host '== e3: anchor-mismatch (test seam: DRAGLINT_CYCLEFIX_TEST_TAMPER edits the staged text in memory only)' -ForegroundColor Cyan
  $r0 = Run-Patched 'e3c' { param($p) }
  Check 'e3: CONTROL without the seam the same plan is mechanical (exit 0)' ($r0.Exit -eq 0) $r0.Out
  $r = Run-Patched 'e3' { param($p) } @{ DRAGLINT_CYCLEFIX_TEST_TAMPER = 'DemoLogger.pas|llWarn, llError|llWarn, llXError' }
  $kinds = if ($r.Json) { @($r.Json.cycles[0].refusals | ForEach-Object { $_.kind }) } else { @() }
  Check 'e3: exit 1, refusal anchor-mismatch' ($r.Exit -eq 1 -and $kinds -contains 'anchor-mismatch') $r.Out
  Check 'e3: shadow empty or absent' ($r.ShadowFiles -eq 0) "files=$($r.ShadowFiles)"
  Check 'e3: stderr announces the seam (dry run)' ($r.Err.Contains('cycles --fix: TEST TAMPER active (dry run only)')) $r.Err
  Check 'e3: CONTROL no notice when the variable is unset' (-not $r0.Err.Contains('TEST TAMPER')) $r0.Err
  $ra = Run-Patched 'e3a' { param($p) } @{ DRAGLINT_CYCLEFIX_TEST_TAMPER = 'DemoLogger.pas|llWarn, llError|llWarn, llXError' } @('--apply')
  Check 'e3: with --apply the seam is NOT honoured: no notice, exit 2, nothing staged' (-not $ra.Err.Contains('TEST TAMPER') -and $ra.Exit -eq 2 -and $ra.ShadowFiles -eq 0) "exit=$($ra.Exit) files=$($ra.ShadowFiles) $($ra.Err)"

  Write-Host '== e4: --shadow-out must be empty' -ForegroundColor Cyan
  $busy = Join-Path $WorkDir 'busy'
  New-Item -ItemType Directory -Force $busy | Out-Null
  [IO.File]::WriteAllText((Join-Path $busy 'keep.txt'), 'x')
  $out = (& $Exe cycles --fix --project (Join-Path $dproj 'CircularDemo.dproj') --db $ddb --no-compile --library-db none --shadow-out $busy --format json 2>$null | Out-String)
  Check 'e4: exit 2, "shadow-out dir not empty"' ($LASTEXITCODE -eq 2 -and $out -match 'shadow-out dir not empty') $out
  Check 'e4: the directory is untouched' ((Test-Path (Join-Path $busy 'keep.txt')) -and @(Get-ChildItem $busy -Recurse -File).Count -eq 1) ''
} finally {
  Pop-Location
}
Check 'z1: the real library DBs are unchanged (size + mtime)' ((Get-LibStamp) -eq $stampBefore) ''

Write-Host ("{0} PASS" -f $script:Passed)
Remove-Scratch
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
