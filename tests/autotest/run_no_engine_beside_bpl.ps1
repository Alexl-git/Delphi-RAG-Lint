<#
  run_no_engine_beside_bpl.ps1 -- nothing may plant a drag-lint engine beside
  the 32-bit BPL, or in third_party\dll\.

  Why this exists
  ---------------
  Owner ruling 2026-08-26: only the 64-bit engine is needed. The BPL is the one
  32-bit artifact, because bds.exe is.

  On 2026-08-26 the IDE menu spawned drag-lint 0.41.0-alpha of 2026-06-10 and
  reported `Unknown argument: --platform`. Three mechanisms had to line up, and
  each looked reasonable alone:

    1. LoadSettings expanded a bare exe name and probed the Win64 sibling with a
       missing separator, so that branch could never hit (see
       run_path_separator_guard.ps1);
    2. it then fell back to <bpl-dir>\drag-lint.exe;
    3. AutoPullStagedExe kept RE-CREATING that file at every plugin init, from
       a C:\TEMP1\bpl_staging\ copy that had not been refreshed in ten weeks.

  (3) is the one that made the cleanup fail. Its skip test -- staged is not
  newer than deployed -- only applies when the deployed file EXISTS, so deleting
  the stale engine caused an UNCONDITIONAL re-copy. Removing the trap re-armed
  it, 13 seconds before the next resolution read the result.

  All three are fixed. This guard pins (2) and (3): no source auto-pulls an
  engine into the BPL directory, and no build/deploy script stages one into
  third_party\dll-win32\ or third_party\dll\ -- both of which win bare-name
  resolution ahead of dll-win64\.

  A retired script that merely PRINTS these paths is fine; only a copy is a
  failure. The detectors are self-tested against synthetic offending lines
  below, so this guard cannot pass by matching nothing.
#>
param([string]$Repo = "$PSScriptRoot\..\..")

$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) { 'PASS' } else { 'FAIL' }
  $color  = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}

$Repo = (Resolve-Path $Repo).Path
Write-Host '== no engine beside the BPL ==' -ForegroundColor Cyan

# A source-level auto-pull of an engine from a staging directory. Requires a
# STRING LITERAL: prose that merely names the path (this file, the tombstone in
# DragLint.Plugin.Editor.pas) is documentation, not a mechanism.
$autoPull = [regex]"(?i)'[^']*bpl_staging[^']*drag-lint\.exe"
# A script COPY whose destination is a 32-bit engine location.
$stageCopy = [regex]'(?i)^\s*(copy|xcopy|robocopy|Copy-Item)\b.*(dll-win32|third_party.dll).{0,3}drag-lint\.exe'

# --- self-test: the detectors must fire on known-bad input ------------------
Check 'positive control: auto-pull detector fires' `
  ($autoPull.IsMatch("STAGING_PATH = 'C:\TEMP1\bpl_staging\drag-lint.exe';"))
Check 'positive control: stage-copy detector fires' `
  ($stageCopy.IsMatch('copy /Y "%ROOT%\src\cli\Win32\Debug\drag-lint.exe" "%ROOT%\third_party\dll-win32\drag-lint.exe"'))
Check 'negative control: a REM/comment mentioning the path is not a copy' `
  (-not $stageCopy.IsMatch('REM stage a WIN32 engine into third_party\dll-win32\drag-lint.exe'))

# --- the real scan ----------------------------------------------------------
$exts  = @('.pas','.dpr','.inc','.bat','.cmd','.ps1')
$files = @(Get-ChildItem -LiteralPath $Repo -Recurse -File -ErrorAction SilentlyContinue |
           Where-Object { $exts -contains $_.Extension.ToLowerInvariant() } |
           Where-Object { $_.FullName -notlike '*\.git\*' } |
           Where-Object { $_.FullName -notlike '*_D-RAG*' } |
           Where-Object { $_.FullName -notlike '*\node_modules\*' } |
           Where-Object { $_.FullName -notlike '*\third_party\delphi-tree-sitter\*' } |
           Where-Object { $_.Name -ne 'run_no_engine_beside_bpl.ps1' })
Check 'files scanned' ($files.Count -gt 0) "($($files.Count))"

$pullHits  = New-Object System.Collections.Generic.List[string]
$stageHits = New-Object System.Collections.Generic.List[string]
foreach ($f in $files) {
  $n = 0
  foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
    $n++
    $rel = $f.FullName.Substring($Repo.Length + 1)
    if ($autoPull.IsMatch($line))  { $pullHits.Add(("{0}:{1}: {2}"  -f $rel, $n, $line.Trim())) }
    if ($stageCopy.IsMatch($line)) { $stageHits.Add(("{0}:{1}: {2}" -f $rel, $n, $line.Trim())) }
  }
}

Check 'nothing auto-pulls an engine from a staging directory' ($pullHits.Count -eq 0) `
  $(if ($pullHits.Count -gt 0) { "($($pullHits.Count) offender(s))" } else { '' })
foreach ($h in $pullHits) { Write-Host "        $h" -ForegroundColor Yellow }

Check 'no script stages an engine into a 32-bit engine location' ($stageHits.Count -eq 0) `
  $(if ($stageHits.Count -gt 0) { "($($stageHits.Count) offender(s))" } else { '' })
foreach ($h in $stageHits) { Write-Host "        $h" -ForegroundColor Yellow }

Write-Host ''
if ($script:Failed) { Write-Host 'NO ENGINE BESIDE BPL GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'NO ENGINE BESIDE BPL GUARD: PASS' -ForegroundColor Green
exit 0
