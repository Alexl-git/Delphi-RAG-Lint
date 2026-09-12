# Guard: lint-all PROGRESS must not sit at 100% while the run is still working.
#
# THE DEFECT. The per-file scan computed Pct = (FileIdx+1)*100 div N, so the
# progress bar reached 100% the instant the last file was scanned -- and then
# THIRTEEN more phases ran (project-rules, class-metrics, missing-doc,
# doc-drift, duplicate-code, interface-cycles, layering, unit-not-in-dpr,
# used-unit-resolvable, the exclude_paths / ownership / --project filters, and
# finalize+output) with no progress signal at all. On ORM3 that is a long,
# silent wait at "100%", which reads as a hang.
#
# PROGRESS IS A CONTRACT, NOT DECORATION. The IDE plugin parses the digit run
# before '%' out of these lines to drive its bar (DragLint.Plugin.JobQueue.pas),
# so the shape `lint-all: ... NN% ...` must be preserved while the SCALE changes.
#
# NOTE FOR THE NEXT READER: run_lintall_infers_project_for_unit_not_in_dpr.ps1
# deliberately filters these progress lines OUT of its assertions, because a
# bare filename match was satisfied by the progress output alone and passed
# against an unfixed build. Do not "fix" that by matching progress here either:
# every assertion below is about the PERCENT SEQUENCE, not about findings.
#
# Usage: pwsh -File tests/autotest/run_lintall_progress_phases.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-lintall-progress"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force $WorkDir | Out-Null

# A few real units so the per-file loop has more than one step to report.
1..4 | ForEach-Object {
    $n = $_
    $src = @(
        "unit uProg$n;",
        "interface",
        "type",
        "  TThing$n = class",
        "  public",
        "    procedure Go;",
        "  end;",
        "implementation",
        "procedure TThing$n.Go;",
        "begin",
        "end;",
        "end."
    ) -join "`r`n"
    [IO.File]::WriteAllText((Join-Path $WorkDir "uProg$n.pas"), $src + "`r`n", [Text.Encoding]::ASCII)
}
$db = Join-Path $WorkDir 'prog.sqlite'
& $Exe index $WorkDir --db $db --rebuild *> $null
Check 'fixture indexed' (Test-Path $db) $db

# stderr carries the progress; 2>&1 merges it so PowerShell can see it.
$raw  = (& $Exe lint-all --db $db 2>&1 | Out-String)
$prog = @($raw -split "`r?`n" | Where-Object { $_ -match '^lint-all:' -and $_ -match '(\d+)%' })
$pcts = @($prog | ForEach-Object { [int]([regex]::Match($_, '(\d+)%').Groups[1].Value) })

Write-Host ("  progress lines: {0}" -f $prog.Count) -ForegroundColor DarkGray
if ($pcts.Count) { Write-Host ("  percents: {0}" -f ($pcts -join ',')) -ForegroundColor DarkGray }

# CONTROL -- if there is no progress at all, every assertion below is vacuous.
Check 'CONTROL progress lines are emitted at all' ($prog.Count -ge 1) `
      'no lint-all: NN% lines -- the rest of this guard would pass vacuously'

# The per-file SCAN must stop short of 100 so the tail has somewhere to go.
$scan = @($prog | Where-Object { $_ -match '^lint-all: \[\d+/\d+\]' } |
          ForEach-Object { [int]([regex]::Match($_, '(\d+)%').Groups[1].Value) })
Check 'the per-file scan never reports 100%' `
      (($scan.Count -ge 1) -and (($scan | Measure-Object -Maximum).Maximum -le 95)) `
      ("scan max = " + $(if ($scan.Count) { ($scan | Measure-Object -Maximum).Maximum } else { 'n/a' }))

# THE POINT OF THE CHANGE -- the tail phases must report.
$tail = @($prog | Where-Object { $_ -notmatch '^lint-all: \[\d+/\d+\]' })
Check 'at least one POST-SCAN phase reports progress' ($tail.Count -ge 1) `
      'the silent tail is the defect; a named phase line must appear after the scan'
Check 'a post-scan phase names itself (not just a number)' `
      (@($tail | Where-Object { $_ -match '%\s+\S' }).Count -ge 1) `
      'the line should say WHICH phase is running, e.g. "lint-all: 94% duplicate-code"'

# Monotonic: a bar that goes backwards is worse than one that sticks.
$mono = $true
for ($i = 1; $i -lt $pcts.Count; $i++) { if ($pcts[$i] -lt $pcts[$i-1]) { $mono = $false } }
Check 'the percent sequence never goes backwards' $mono ($pcts -join ',')

# 100% means DONE -- it must be the last thing said, not the first.
if ($pcts.Count -ge 1) {
    $firstHundred = [Array]::IndexOf($pcts, 100)
    Check '100% appears only as the FINAL percent (or not at all)' `
          (($firstHundred -lt 0) -or ($firstHundred -eq ($pcts.Count - 1))) `
          ("100% at index $firstHundred of " + $pcts.Count)
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }