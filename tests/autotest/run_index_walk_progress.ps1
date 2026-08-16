<#
  run_index_walk_progress.ps1 -- the folder walk reports n/total with an ETA, and
  the total counts only files the walk would actually index.

  WHAT THIS FIXES:
    TIndexer.ReportProgress printed one line per file with no counter, so an
    hours-long library reindex was indistinguishable from a hang -- which is a
    large part of why the Win32 library rebuild abort was hard to diagnose.
    IndexFolder now walks TWICE: once in count-only mode through the SAME
    WalkAndIndex with the SAME filters and ignore-stack, then for real.

  THE POSITIVE CONTROL IS THE DENOMINATOR, NOT THE LINE:
    Asserting merely that "a progress line appeared" would pass against the one
    way this can silently lie -- a pre-count that enumerates the directory itself
    instead of reusing the walk's admission rules. Such a count would include
    Notes.txt (no parser handles the extension) and __history\Stale.pas (a pruned
    directory), and would report 5 while the run only ever indexes 3. So the
    fixture deliberately contains both kinds of excluded file and the suite
    asserts the total is exactly 3.

  AND THE STDOUT CONTRACT IS ITSELF A CONTROL:
    The counter goes to STDERR on purpose. Several suites regex the per-file
    stdout line (run_index_fingerprint_commit.ps1 among them), so this asserts
    that line is still present and still in its old shape -- adding progress
    must not have moved it.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-walk-progress"
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
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$SrcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $SrcDir | Out-Null
New-Item -ItemType Directory (Join-Path $SrcDir '__history') | Out-Null

function Write-Unit([string]$Path, [string]$UnitName) {
  $body = @"
unit $UnitName;
interface
procedure Go;
implementation
procedure Go;
begin
end;
end.
"@
  $norm = ($body -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# THREE indexable units ...
Write-Unit (Join-Path $SrcDir 'uAlpha.pas') 'uAlpha'
Write-Unit (Join-Path $SrcDir 'uBeta.pas' ) 'uBeta'
Write-Unit (Join-Path $SrcDir 'uGamma.pas') 'uGamma'
# ... and two files the walk must NOT count.
[System.IO.File]::WriteAllText((Join-Path $SrcDir 'Notes.txt'), "just prose`r`n", [System.Text.Encoding]::ASCII)
Write-Unit (Join-Path $SrcDir '__history\uStale.pas') 'uStale'

$Db = Join-Path $WorkDir 'walk.sqlite'
$OutFile = Join-Path $WorkDir 'stdout.txt'
$ErrFile = Join-Path $WorkDir 'stderr.txt'
$p = Start-Process -FilePath $Exe -ArgumentList @('index', $SrcDir, '--db', $Db) `
       -RedirectStandardOutput $OutFile -RedirectStandardError $ErrFile `
       -NoNewWindow -Wait -PassThru
$so = Get-Content $OutFile -Raw
$se = Get-Content $ErrFile -Raw
if ($null -eq $so) { $so = '' }
if ($null -eq $se) { $se = '' }

Write-Host ("  index exit {0}" -f $p.ExitCode) -ForegroundColor DarkGray

$totalMatch = [regex]::Match($se, 'walking (\d+) file\(s\)')
$total = if ($totalMatch.Success) { [int]$totalMatch.Groups[1].Value } else { -1 }
$counters = @([regex]::Matches($se, '\[(\d+)/(\d+)\]') | ForEach-Object { $_.Value })
Write-Host ("  announced total: {0}   counters: {1}" -f $total, ($counters -join ' ')) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'The walk announces a denominator, and it is the walk-admitted count' -ForegroundColor Cyan
Check 'a total is announced on stderr' ($totalMatch.Success)
Check 'total is 3, not 5 -- excluded files are NOT counted' ($total -eq 3) "total=$total"
if ($total -eq 5) {
  Write-Host '  !! 5 means the pre-count enumerated the directory instead of reusing' -ForegroundColor Yellow
  Write-Host '  !! the walk admission rules -- the exact way this can silently lie.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Per-file counters advance to the announced total' -ForegroundColor Cyan
Check 'three counters emitted'      ($counters.Count -eq 3) "got $($counters.Count)"
Check 'first counter is [1/3]'      ($counters -contains '[1/3]') "got=$($counters -join ' ')"
Check 'last counter is [3/3]'       ($counters -contains '[3/3]') "got=$($counters -join ' ')"
Check 'an ETA accompanies progress' ($se -match 'left')

Write-Host ''
Write-Host 'CONTROL: the files really were indexed, and only those three' -ForegroundColor Cyan
Check 'uAlpha indexed' ($so -match 'uAlpha\.pas -> \d+ symbols')
Check 'uBeta indexed'  ($so -match 'uBeta\.pas -> \d+ symbols')
Check 'uGamma indexed' ($so -match 'uGamma\.pas -> \d+ symbols')
Check 'the .txt was never indexed'        (-not ($so -match 'Notes\.txt'))
Check 'the __history unit was never indexed' (-not ($so -match 'uStale\.pas'))

Write-Host ''
Write-Host 'CONTROL: the stdout line other suites regex is unchanged' -ForegroundColor Cyan
Check 'stdout still carries the old per-file shape' `
      ($so -match '\S+\.pas -> \d+ symbols, \d+ refs, \d+ errors')
Check 'the counter did NOT leak into stdout' (-not ($so -match '\[\d+/\d+\]'))

Write-Host ''
if ($script:Failed) {
  Write-Host '--- stderr ---' -ForegroundColor DarkGray; Write-Host $se
  Write-Host '--- stdout ---' -ForegroundColor DarkGray; Write-Host $so
  Write-Host 'FAIL' -ForegroundColor Red; exit 1
} else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
