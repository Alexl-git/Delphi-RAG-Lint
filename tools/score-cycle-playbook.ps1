<#
  score-cycle-playbook.ps1 -- score a model's attempt at a `cycles --plan`
  playbook against the four criteria of the followability protocol
  (docs\INBOX-test-cycle-playbook-followability-haiku-flash.md, CYC-4 of
  BACKLOG-TRIAGE-2026-09-28).

  WHY. The end-to-end proof (hand the report to a model, let it edit a copy,
  then check the result) was run three times BY HAND. Every future change to the
  playbook's shape needs the same four checks; doing them by hand is how a run
  gets scored generously. This script applies nothing -- it only reads the two
  trees and the report, builds, indexes a scratch copy, and prints a verdict.

  THE FOUR CRITERIA (decided before any run, never after):
    1. CYCLE  -- `drag-lint cycles` on a fresh index of the EDITED tree prints
                 the block the report's checklist says it must print (unit order
                 inside a group ignored, as the report itself allows; info lines
                 ignored).
    2. BUILD  -- msbuild of the edited project: 0 errors. With -RunExe, the
                 built program's stdout also equals the ORIGINAL program's.
    3. CUT    -- the new files are exactly the units the report nominates in
                 its "Create" checklist items -- no more, no fewer.
    4. SCOPE  -- every changed file is one the report names (an "Apply every
                 edit listed for" item or a "Create" item); nothing deleted.

  USAGE
    pwsh -File tools\score-cycle-playbook.ps1 -Original <dir> -Edited <dir>
         -Report <report.md|.txt> -Project <X.dproj file name> [-Platform Win32]
         [-Config Debug] [-RunExe] [-Exe <drag-lint.exe>] [-Json]
  Exit 0 when all four pass, 1 when any fails, 2 on a usage error.
  Build outputs land inside the -Edited (and, with -RunExe, -Original) trees:
  pass COPIES, never a working tree.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$Original,
  [Parameter(Mandatory)] [string]$Edited,
  [Parameter(Mandatory)] [string]$Report,
  [Parameter(Mandatory)] [string]$Project,
  [string]$Platform = 'Win32',
  [string]$Config   = 'Debug',
  [switch]$RunExe,
  [string]$Exe      = "$PSScriptRoot\..\third_party\dll-win64\drag-lint.exe",
  [switch]$Json
)
$ErrorActionPreference = 'Stop'
foreach ($p in $Original, $Edited, $Report) {
  if (-not (Test-Path -LiteralPath $p)) { Write-Host "usage: not found: $p" -ForegroundColor Red; exit 2 }
}
$Original = (Resolve-Path $Original).Path
$Edited   = (Resolve-Path $Edited).Path
$exePath  = (Resolve-Path $Exe).Path
$reportText = [IO.File]::ReadAllText((Resolve-Path $Report).Path)
$result = [ordered]@{}

# ---- what the report says ----------------------------------------------------
# The paths it prints are relative to where `cycles` ran; only the LEAF names are
# compared, because the model's copy lives somewhere else.
$named   = @([regex]::Matches($reportText, 'Apply every edit listed for `([^`]+)`') | ForEach-Object { $_.Groups[1].Value.ToLower() })
$created = @([regex]::Matches($reportText, '\[ \] Create `([^`]+)`') | ForEach-Object { (Split-Path $_.Groups[1].Value -Leaf).ToLower() })
$expM    = [regex]::Match($reportText, 'It must print exactly:\s*\r?\n```text\r?\n(.*?)\r?\n```', 'Singleline')
if (($named.Count -eq 0) -or ($created.Count -eq 0) -or -not $expM.Success) {
  Write-Host 'usage: the report has no checklist (Apply/Create items and the expected cycles block) -- is it a `cycles --plan` report?' -ForegroundColor Red
  exit 2
}
function Normalize-Cycles([string]$Text) {
  # One line per non-informational line; inside "[N units] a <-> b <-> c" the
  # unit order is not significant, so the names are sorted.
  $out = @()
  foreach ($l in ($Text -split "\r?\n")) {
    $t = $l.TrimEnd()
    if ($t -eq '' -or $t -match '^\(loaded|^drag-lint: note:|^\s+resolver:') { continue }
    $m = [regex]::Match($t, '^(\s*\[\d+ units\]\s+)(.+?)(\s{2,}\(.*)$')
    if ($m.Success) {
      $units = ($m.Groups[2].Value -split '\s*<->\s*' | Sort-Object) -join ' <-> '
      $t = $m.Groups[1].Value + $units + $m.Groups[3].Value
    }
    $out += $t
  }
  return ($out -join "`n")
}
$expected = Normalize-Cycles $expM.Groups[1].Value

# ---- criterion 4 and 3: what changed ------------------------------------------
function Get-Tree([string]$Root) {
  $h = @{}
  foreach ($f in Get-ChildItem -LiteralPath $Root -Recurse -File |
                  Where-Object { $_.FullName -notmatch '\\(Win32|Win64|_D-RAG|__history|__recovery)\\' -and
                                 $_.Extension -notmatch '^\.(dcu|exe|identcache|local|res|dsk|stat)$' -and
                                 $_.Name -notlike 'score-build.*' }) {   # this script's own build files
    $rel = $f.FullName.Substring($Root.Length).TrimStart('\').ToLower()
    $h[$rel] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
  }
  return $h
}
$before = Get-Tree $Original
$after  = Get-Tree $Edited
$changed = @($after.Keys | Where-Object { $before.ContainsKey($_) -and $before[$_] -ne $after[$_] } | Sort-Object)
$added   = @($after.Keys | Where-Object { -not $before.ContainsKey($_) } | Sort-Object)
$deleted = @($before.Keys | Where-Object { -not $after.ContainsKey($_) } | Sort-Object)
$allowed = @($named) + @($created)
$outside = @(@($changed) + @($added) | Where-Object { $allowed -notcontains (Split-Path $_ -Leaf) })
$result['4-SCOPE'] = [ordered]@{
  pass    = (($outside.Count -eq 0) -and ($deleted.Count -eq 0))
  changed = $changed; added = $added; deleted = $deleted; outside_the_report = $outside
}
$addedLeaves = @($added | ForEach-Object { Split-Path $_ -Leaf })
$missingNew  = @($created | Where-Object { $addedLeaves -notcontains $_ })
$extraNew    = @($addedLeaves | Where-Object { $created -notcontains $_ })
$result['3-CUT'] = [ordered]@{
  pass = (($missingNew.Count -eq 0) -and ($extraNew.Count -eq 0))
  nominated = $created; missing = $missingNew; unexpected = $extraNew
}

# ---- criterion 2: build -------------------------------------------------------
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
function Invoke-Build([string]$Root) {
  $dproj = Join-Path $Root $Project
  $log   = Join-Path $Root 'score-build.log'
  $bat   = Join-Path $Root 'score-build.bat'
  $lines = @('@echo off', ('call "{0}"' -f $rs), ('cd /d "{0}"' -f $Root),
             ('msbuild /t:Build /p:Config={0} /p:Platform={1} /v:minimal "{2}" > "{3}" 2>&1' -f $Config, $Platform, $dproj, $log),
             # Redirection FIRST: `echo X=%ERRORLEVEL%>> f` expands to `X=0>> f`,
             # and cmd reads `0>>` as a redirect of handle 0 -- the line is lost.
             ('>> "{0}" echo BUILD_EXITCODE=%ERRORLEVEL%' -f $log))
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -NoNewWindow -Wait | Out-Null
  $text = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '' }
  $errors = @([regex]::Matches($text, '(?m)^.*\b(error|fatal) [EF]\d{4}\b.*$') | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
  return [pscustomobject]@{ Ok = ($text -match 'BUILD_EXITCODE=0') -and ($errors.Count -eq 0); Errors = $errors; Log = $log }
}
function Invoke-Program([string]$Root) {
  $name = [IO.Path]::GetFileNameWithoutExtension($Project) + '.exe'
  $exe  = Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $name | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $exe) { return $null }
  return ((& $exe.FullName 2>&1 | ForEach-Object { "$_" }) -join "`n")
}
$b = Invoke-Build $Edited
$build = [ordered]@{ pass = $b.Ok; errors = $b.Errors; log = $b.Log }
if ($RunExe -and $b.Ok) {
  $bo = Invoke-Build $Original
  $outE = Invoke-Program $Edited
  $outO = if ($bo.Ok) { Invoke-Program $Original } else { $null }
  $build['program_output_identical'] = ($null -ne $outE) -and ($outE -ceq $outO)
  $build['pass'] = $build['pass'] -and $build['program_output_identical']
}
$result['2-BUILD'] = $build

# ---- criterion 1: the cycle ----------------------------------------------------
$scratchDb = Join-Path ([IO.Path]::GetTempPath()) ("score-cycles-{0}.sqlite" -f $PID)
try {
  & $exePath index --project (Join-Path $Edited $Project) --db $scratchDb 2>&1 | Out-Null
  $actualRaw = ((& $exePath cycles --db $scratchDb 2>&1 | ForEach-Object { "$_" }) -join "`n")
} finally {
  foreach ($s in $scratchDb, "$scratchDb-wal", "$scratchDb-shm") { if (Test-Path -LiteralPath $s) { [IO.File]::Delete($s) } }
}
$actual = Normalize-Cycles $actualRaw
$result['1-CYCLE'] = [ordered]@{ pass = ($actual -ceq $expected); expected = $expected; actual = $actual }

# ---- verdict --------------------------------------------------------------------
$all = ($result['1-CYCLE'].pass -and $result['2-BUILD'].pass -and $result['3-CUT'].pass -and $result['4-SCOPE'].pass)
if ($Json) {
  $result['pass'] = $all
  $result | ConvertTo-Json -Depth 6
} else {
  foreach ($k in $result.Keys) {
    $r = $result[$k]
    Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$r.pass]), $k) -ForegroundColor (@('Red','Green')[[int][bool]$r.pass])
  }
  if (-not $result['1-CYCLE'].pass) { Write-Host "  expected:`n$($result['1-CYCLE'].expected)`n  actual:`n$($result['1-CYCLE'].actual)" }
  if (-not $result['2-BUILD'].pass) { $result['2-BUILD'].errors | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" } }
  if (-not $result['3-CUT'].pass)   { Write-Host "  missing: $($result['3-CUT'].missing -join ', ')  unexpected: $($result['3-CUT'].unexpected -join ', ')" }
  if (-not $result['4-SCOPE'].pass) { Write-Host "  outside the report: $($result['4-SCOPE'].outside_the_report -join ', ')  deleted: $($result['4-SCOPE'].deleted -join ', ')" }
  Write-Host ''
  Write-Host (@('SCORE: FAIL','SCORE: PASS 4/4')[[int]$all]) -ForegroundColor (@('Red','Green')[[int]$all])
}
exit (@(1, 0)[[int]$all])
