<#
  run_v156_THR-R.ps1 -- 1.56 lane THR-R (G-05): lock-order-inversion. Two routines take the same two
  locks in opposite order (directly, or through a called routine), so two threads can deadlock.
  Project-wide rule (lint-all), on the lock sites of DRagLint.Query.LockSites (lane THR-S).

  Fixture tests\fixtures\v156\THR-R (thrOrder.pas, thrOrder2.pas), copied and indexed into a private
  db with the engine under test. A fixture line ending in `// HIT-<NAME>` must carry exactly one
  finding; no other line may carry one (`// QUIET-<NAME>` lines are named in the report when they do).

    c0   the rule is in the catalog (rules --json) and ON by default
    c1   lint-all (no --rule) reports the rule: positive control for every silent case below
    hit  one check per HIT marker: AB / BA (direct), CALL / CALL-REV (lock taken by a callee),
         CALL2 / CALL2-REV (two calls deep), RW-WRITE / RW-READ (a writer on one side),
         GLOBAL-XY / GLOBAL-YX (unit-level locks, two units)
    quiet one check per QUIET marker: same order, parameters, locals, a callee that takes no lock, a call
         after the lock was left, a common gate lock, a try-enter, readers on both sides, a re-entered
         lock, a sequential pair
    c2   the findings are exactly the HIT lines (nothing leaks)
    c3   the AB message names both locks and the routine that takes them in the other order
    c4   the CALL message names the called routine
    c5   --rule lock-order-inversion gives the same lines

  With the pre-lane engine c0, c1, every hit, c3, c4 FAIL (RED); the quiet checks pass vacuously,
  which is why c1 and the hit twins exist.

  Usage: pwsh -File tests\autotest\run_v156_THR-R.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "C:\TEMP\draglint_v156_thrr_$PID"
)
. (Join-Path $PSScriptRoot 'lib\WorkDirCleanup.ps1')
try {
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $Root 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path $Exe)) { Write-Host "SKIP: engine not found: $Exe"; exit 0 }
$Exe  = (Resolve-Path $Exe).Path
# positive-control: lock-order-inversion
$Rule = 'lock-order-inversion'

$script:Fail = 0
$script:Pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "  PASS  $Name" } else { $script:Fail++; Write-Host "  FAIL  $Name  $Detail" }
}

# lint-all --json is a bare array; the line field is start_line. Print raw once, then filter.
function Get-Findings([string]$Db, [string[]]$Extra) {
  $out = (& { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $Db --json @Extra 2>$null }) -join "`n"
  Write-Host ("  raw: " + $out.Substring(0, [Math]::Min(400, $out.Length)))
  if (-not $out.TrimStart().StartsWith('[')) { return @() }
  return @($out | ConvertFrom-Json | ForEach-Object { $_ } | Where-Object { $_.rule -eq $Rule })
}

[void](New-Item -ItemType Directory -Force -Path $WorkDir)
$Src = Join-Path $WorkDir 'src'
Copy-Item (Join-Path $Root 'tests\fixtures\v156\THR-R') $Src -Recurse -Force
$Db = Join-Path $WorkDir 'thrr.sqlite'
Push-Location $WorkDir
try {
  & { $ErrorActionPreference = 'Continue'; & $Exe index $Src --db $Db *> (Join-Path $WorkDir 'index.log') }

  # c0: catalog
  $rulesRaw = (& { $ErrorActionPreference = 'Continue'; & $Exe rules --json 2>$null }) -join "`n"
  # rules --json is {"rules":[{id, default_enabled, ...}], "summary":..}
  $cat = @(($rulesRaw | ConvertFrom-Json | ForEach-Object { $_ }).rules | Where-Object { $_.id -eq $Rule })
  if ($cat.Count -gt 0) { Write-Host ("  catalog row: id={0} default_enabled={1} severity={2}" -f $cat[0].id, $cat[0].default_enabled, $cat[0].default_severity) }
  Check 'c0 the rule is in the catalog and ON by default' (($cat.Count -eq 1) -and ($cat[0].default_enabled -eq $true)) ("rows " + $cat.Count)

  # markers: '<file>:<line>' -> name
  $Hit = @{}; $Quiet = @{}
  foreach ($f in Get-ChildItem -LiteralPath $Src -Filter *.pas) {
    $n = 0
    foreach ($line in [IO.File]::ReadAllLines($f.FullName)) {
      $n++
      if ($line -match '//\s*HIT-([A-Z0-9-]+)\s*$')   { $Hit["$($f.Name):$n"]   = $Matches[1] }
      if ($line -match '//\s*QUIET-([A-Z0-9-]+)\s*$') { $Quiet["$($f.Name):$n"] = $Matches[1] }
    }
  }
  Write-Host ("  markers: {0} HIT, {1} QUIET" -f $Hit.Count, $Quiet.Count)

  $all = @(Get-Findings $Db @())
  Check 'c1 lint-all (no --rule) reports the rule' ($all.Count -ge 1) ("got " + $all.Count)
  $at = @{}
  foreach ($x in $all) {
    $k = "{0}:{1}" -f [IO.Path]::GetFileName([string]$x.file_path), [int]$x.start_line
    if ($at.ContainsKey($k)) { $at[$k] = @($at[$k]) + $x } else { $at[$k] = @($x) }
  }
  foreach ($k in ($Hit.Keys | Sort-Object)) {
    $cnt = if ($at.ContainsKey($k)) { @($at[$k]).Count } else { 0 }
    Check ("hit   {0} ({1}) fires once" -f $Hit[$k], $k) ($cnt -eq 1) ("got $cnt")
  }
  foreach ($k in ($Quiet.Keys | Sort-Object)) {
    Check ("quiet {0} ({1}) is silent" -f $Quiet[$k], $k) (-not $at.ContainsKey($k))
  }
  $extra = @($at.Keys | Where-Object { -not $Hit.ContainsKey($_) } | Sort-Object)
  Check 'c2 the findings are exactly the HIT lines' (($extra.Count -eq 0) -and ($at.Count -eq $Hit.Count) -and ($Hit.Count -eq 10)) ("extra: " + ($extra -join ' ') + "; lines " + $at.Count + " of " + $Hit.Count)

  $kAB = @($Hit.Keys | Where-Object { $Hit[$_] -eq 'AB' })[0]
  $mAB = if ($kAB -and $at.ContainsKey($kAB)) { [string]@($at[$kAB])[0].message } else { '' }
  Write-Host "  AB message: $mAB"
  Check 'c3 the AB message names both locks and the other routine' (($mAB -match 'FLockA') -and ($mAB -match 'FLockB') -and ($mAB -match 'BThenA')) $mAB

  $kCall = @($Hit.Keys | Where-Object { $Hit[$_] -eq 'CALL' })[0]
  $mCall = if ($kCall -and $at.ContainsKey($kCall)) { [string]@($at[$kCall])[0].message } else { '' }
  Write-Host "  CALL message: $mCall"
  Check 'c4 the CALL message names the called routine' (($mCall -match 'TakeF') -and ($mCall -match 'FLockF') -and ($mCall -match 'Reverse')) $mCall

  $nar = @(Get-Findings $Db @('--rule', $Rule))
  $narKeys = @($nar | ForEach-Object { "{0}:{1}" -f [IO.Path]::GetFileName([string]$_.file_path), [int]$_.start_line } | Sort-Object)
  Check 'c5 --rule gives the same lines' ((($narKeys -join ' ') -eq ((@($Hit.Keys) | Sort-Object) -join ' ')) -and ($narKeys.Count -gt 0)) ("got " + ($narKeys -join ' '))
}
finally { Pop-Location }

Write-Host ("run_v156_THR-R: {0} passed, {1} failure(s)" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
exit 0
} finally { Remove-WorkDir $WorkDir -Keep:($env:DL_KEEP_WORKDIR -eq '1') }
