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
  C:\TEMP\draglint_cyclefix_<pid>\ is announced and exists.
  The platform library is never opened in place: R2 uses a scratch copy (SKIPped without one).
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-shadow-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite'
)
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
  $txt = (& $Exe cycles --fix --project (Join-Path $dproj 'CircularDemo.dproj') --db $ddb --no-compile --library-db none 2>$null | Out-String)
  $m = [regex]::Match($txt, '(?m)^Shadow tree: (.+?)\s*$')
  Check 'c3: text output announces "Shadow tree: C:\TEMP\draglint_cyclefix_<pid>"' ($m.Success -and $m.Groups[1].Value -match '^C:\\TEMP\\draglint_cyclefix_\d+\\?$') $txt
  Check 'c3: that directory exists and holds files' ($m.Success -and (Test-Path $m.Groups[1].Value) -and (@(Get-ChildItem $m.Groups[1].Value -Recurse -File).Count -gt 0)) ''
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

  Write-Host '== e1: a non-ASCII char in a line the recipe copies into a new unit' -ForegroundColor Cyan
  # 0xE9 (e-acute, cp1252) in the doc comment of TDemoLogLevel, which Part A moves into a new unit.
  $r = Run-Patched 'e1' { param($p) Patch-Bytes (Join-Path $p 'DemoLogger.pas') 'Severity of a log line' ([byte[]](0x53,0xE9,0x76,0xE9,0x72,0x69,0x74,0xE9)) }
  $kinds = if ($r.Json) { @($r.Json.cycles[0].refusals | ForEach-Object { $_.kind }) } else { @() }
  Check 'e1: exit 1, refusal non-ascii-text' ($r.Exit -eq 1 -and $kinds -contains 'non-ascii-text') $r.Out
  Check 'e1: nothing staged (shadow empty or absent)' ($r.ShadowFiles -eq 0) "files=$($r.ShadowFiles)"

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
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
