<#
  run_cyclefix_plan_wording.ps1 -- E18 Task 3b: three wording defects of `cycles --plan`.

  (a) A companion type pulled into a move only by a moved var (TDemoSettings, needed by
      GDemoSettings) used to print NO "Used by" line, which reads as "nobody uses it". It now
      prints `   - Used by: only the moved var `GDemoSettings``. Needs the demo AFTER Part A of
      cycle 1 (applied here with tools\follow-cycle-plan.ps1), then re-indexed and re-planned.
  (b) A routine that blocks an edge, whose signature types all resolve OUTSIDE the cycle, names
      the unit a pointer / event could be declared in instead of the generic "it is a routine".
      Since E18 T5 the plan CUTS that edge (recipe R1) and names the unit the pointer goes into.
  (c) The `(loaded defaults from ...)` note is a STDERR line: the plan on stdout must not hold
      it, and must end with the plan's own last line. Hard positive control: the note IS on stderr.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cycle-wording-$PID"
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
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Runs `cycles --plan`; returns stdout and stderr captured SEPARATELY.
function Get-Plan([string]$Db, [string]$Tag) {
  $o = Join-Path $WorkDir "plan-$Tag.out"; $e = Join-Path $WorkDir "plan-$Tag.err"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @('cycles', '--db', ('"' + $Db + '"'), '--edges', '--causes', '--plan', '--format', 'text') `
    -RedirectStandardOutput $o -RedirectStandardError $e
  return @{ Exit = $p.ExitCode; Out = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText($e); File = $o }
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
# An empty defaults file in the work dir makes the engine print its note, so (c) is not vacuous.
[IO.File]::WriteAllText((Join-Path $WorkDir '.drag-lint.json'), '{}')
$root = Join-Path $WorkDir 'circular-demo'
New-Item -ItemType Directory -Force $root | Out-Null
Get-ChildItem (Join-Path $Repo 'circular-demo') -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) -Force }
$db = Join-Path $WorkDir 'demo.sqlite'
& $Exe index --project (Join-Path $root 'CircularDemo.dproj') --db $db *> (Join-Path $WorkDir 'index1.log')
Check 'demo indexed' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

Write-Host '== (c) trailer on stderr' -ForegroundColor Cyan
$p0 = Get-Plan $db '0'
Check 'plan exit 0' ($p0.Exit -eq 0) "exit=$($p0.Exit)"
Check 'c1 stdout has no "(loaded defaults" note' ($p0.Out -notmatch 'loaded defaults') ''
Check 'c2 stdout ends with plan text, not a note' (($p0.Out.TrimEnd() -split "`r?`n")[-1] -notmatch '^\(') (($p0.Out.TrimEnd() -split "`r?`n")[-1])
$ctl = Get-Plan $db 'ctl'
$withCfg = $ctl.Err -match 'loaded defaults'
# Hard control: this runner wrote .drag-lint.json itself, so a missing note means (c1/c2) are vacuous.
Check 'c3 control: the note is on stderr (defaults file written by this runner)' $withCfg ('stderr=[' + $ctl.Err.Trim() + ']')

Write-Host '== (b) routine edge in cycle 3' -ForegroundColor Cyan
$flat = ($p0.Out -replace '\s+', ' ')
$wantB = 'Cut the edge `demoblueprint -> demoblueprint.viewmodel` by **routine-call inversion**: `demoblueprint` takes only the routine `DemoBlueprintViewModelCreate` from `demoblueprint.viewmodel`, and every type of its signature is declared outside this cycle. `demoblueprint` calls it through a procedural variable declared in `DemoBlueprint.Interfaces` instead.'
Check 'b1 edge line names the routine and the interface unit' ($flat.Contains($wantB))

Write-Host '== (a) companion type after Part A' -ForegroundColor Cyan
$before = (Get-ChildItem $root -Filter *.pas | Sort-Object Name | ForEach-Object { (Get-FileHash $_.FullName).Hash }) -join ','
$fo = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $p0.File -Cycle 1 -Root $root 2>&1 | Out-String
$rcA = $LASTEXITCODE
$after = (Get-ChildItem $root -Filter *.pas | Sort-Object Name | ForEach-Object { (Get-FileHash $_.FullName).Hash }) -join ','
Check 'Part A of cycle 1 applied (exit 0)' ($rcA -eq 0) ('exit=' + $rcA + ' ' + ($fo.Trim() -replace "`r?`n", ' | '))
Check 'Part A changed the demo sources' ($before -ne $after)
& $Exe index --project (Join-Path $root 'CircularDemo.dproj') --db $db *> (Join-Path $WorkDir 'index2.log')
Check 'demo re-indexed' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
$p1 = Get-Plan $db '1'
$lines = @($p1.Out -split "`r?`n")
$i = -1
for ($k = 0; $k -lt $lines.Count; $k++) { if ($lines[$k] -match '^\d+\. `TDemoSettings` -- ') { $i = $k; break } }
Check 'a0 Part B item for TDemoSettings found' ($i -ge 0)
if ($i -ge 0) {
  $blk = @()
  for ($k = $i + 1; $k -lt $lines.Count -and $lines[$k] -match '^   '; $k++) { $blk += $lines[$k] }
  Check 'a1 item says "Used by: only the moved var `GDemoSettings`"' ($blk -contains '   - Used by: only the moved var `GDemoSettings`') ($blk -join ' | ')
}
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
