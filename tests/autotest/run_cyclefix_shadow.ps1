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
} finally {
  Pop-Location
}
Check 'z1: the real library DBs are unchanged (size + mtime)' ((Get-LibStamp) -eq $stampBefore) ''

Write-Host ("{0} PASS" -f $script:Passed)
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
