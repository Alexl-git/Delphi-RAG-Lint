#Requires -Version 7.3
<#
  run_v156_VCS1.ps1 -- `lint-all --changed-since <rev>` (1.56 lane VCS-1, gap plan S4 + G-50) on a scratch git
  repository AND a scratch hg repository this runner makes (units DRagLint.Query.Vcs, DRagLint.CLI.ChangedSince).

  Each repository gets the same history from tests\fixtures\v156\VCS-1:
    BASE    commit 1: VcsOld (OldRoutine), VcsEdit (Kept), VcsMove (Moved)
    STEP2   commit 2: VcsEdit gains two lines at the top (every later line moves) and the routine Committed
    STEP3   not committed: VcsEdit loses the line above Kept and gains Pending; VcsNew (Fresh) is not tracked;
            VcsMove.pas is renamed to VcsMoved.pas by the tool
  The rule is unused-public-symbol: one finding per exported routine, on its interface line, named in the message.

  POSITIVE CONTROL (per tool): the run WITHOUT the flag reports all six routines, so the narrowed runs are
  narrowed by the flag and not by an empty report. An engine without the feature fails every narrowed check.

  A missing git, hg or engine is a FAIL, never a skip. Exit 0 only when every check passed.

  Parameters:
    -Repo    repo root (default: two levels above this script)
    -Engine  drag-lint.exe to test (default: <Repo>\src\cli\Win64\Debug\drag-lint.exe)
    -Work    scratch folder (default: %TEMP%\drag-lint-v156-vcs1-<pid>); must be under no .git / .hg
    -Keep    leave the scratch folder in place
#>
[CmdletBinding()]
param([string]$Repo = '',
      [string]$Engine = '',
      [string]$Work = '',
      [switch]$Keep)
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
if (-not $Engine) { $Engine = Join-Path $Repo 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not $Work) { $Work = Join-Path ([IO.Path]::GetTempPath()) "drag-lint-v156-vcs1-$PID" }
$ErrorActionPreference = 'Stop'
$fixture = Join-Path $Repo 'tests\fixtures\v156\VCS-1'
$script:pass = 0
$script:fail = 0

function Check([string]$pName, [bool]$pOk, [string]$pDetail = '') {
  if ($pOk) { $script:pass++; Write-Host "  ok    $pName" }
  else { $script:fail++; Write-Host "  FAIL  $pName  $pDetail" -ForegroundColor Red }
}

# Runs a tool in a folder; a non-zero exit stops the runner (the scratch history must be exact).
function Invoke-Tool([string]$pFolder, [string]$pExe, [string[]]$pArguments) {
  Push-Location -LiteralPath $pFolder
  try {
    $out = & $pExe @pArguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "$pExe $($pArguments -join ' ') failed in ${pFolder}: $out" }
    return $out.Trim()
  } finally { Pop-Location }
}

# Runs the engine from a folder; returns exit code, stdout text and stderr text.
function Invoke-Engine([string]$pFolder, [string[]]$pArguments) {
  $errFile = Join-Path $Work ("err-" + [Guid]::NewGuid().ToString('N') + '.txt')
  Push-Location -LiteralPath $pFolder
  try {
    $out = & $Engine @pArguments 2> $errFile | Out-String
    $code = $LASTEXITCODE
  } finally { Pop-Location }
  $err = if (Test-Path -LiteralPath $errFile) { [IO.File]::ReadAllText($errFile) } else { '' }
  return [pscustomobject]@{ Code = $code; Out = [string]$out; Err = [string]$err }
}

# The routine names of a lint-all --json answer, sorted; '<not json>' when stdout is not the findings array.
function Get-Routines($pRun) {
  $names = @()
  try { $doc = $pRun.Out | ConvertFrom-Json } catch { return '<not json>' }
  foreach ($f in @($doc)) {
    if ($null -eq $f) { continue }
    if ([string]$f.message -match 'Exported routine (\w+) ') { $names += $Matches[1] } else { $names += "?$($f.message)" }
  }
  return (($names | Sort-Object) -join ',')
}

function Copy-Step([string]$pStep, [string]$pInto) {
  foreach ($f in Get-ChildItem -LiteralPath (Join-Path $fixture $pStep) -File) {
    [IO.File]::Copy($f.FullName, (Join-Path $pInto $f.Name), $true)
  }
}

function Test-UnderVcs([string]$pFolder) {
  $d = $pFolder
  while ($d) {
    if ((Test-Path -LiteralPath (Join-Path $d '.git')) -or (Test-Path -LiteralPath (Join-Path $d '.hg'))) { return $d }
    $d = Split-Path -Parent $d
  }
  return ''
}

# One tool: builds the history, indexes the working copy, runs every check.
function Test-Tool([string]$pTool) {
  Write-Host "-- $pTool --"
  $root = Join-Path $Work $pTool
  $wc = Join-Path $root 'repo'
  $db = Join-Path $root 'db\vcs1.sqlite'
  $outside = Join-Path $root 'outside'
  foreach ($d in $wc, (Split-Path -Parent $db), $outside) { [void][IO.Directory]::CreateDirectory($d) }

  Copy-Step 'base' $wc
  if ($pTool -eq 'git') {
    [void](Invoke-Tool $wc 'git' @('init', '-q'))
    foreach ($kv in @(@('user.name', 'vcs1'), @('user.email', 'vcs1@example.invalid'), @('core.autocrlf', 'false'), @('commit.gpgsign', 'false'))) {
      [void](Invoke-Tool $wc 'git' @('config', $kv[0], $kv[1]))
    }
    [void](Invoke-Tool $wc 'git' @('add', '--', '.'))
    [void](Invoke-Tool $wc 'git' @('commit', '-q', '-m', 'base'))
    $base = Invoke-Tool $wc 'git' @('rev-parse', 'HEAD')
    Copy-Step 'step2' $wc
    [void](Invoke-Tool $wc 'git' @('commit', '-q', '-m', 'step2', '--', 'VcsEdit.pas'))
    Copy-Step 'step3' $wc
    [void](Invoke-Tool $wc 'git' @('mv', 'VcsMove.pas', 'VcsMoved.pas'))
    $tip = 'HEAD'
  } else {
    [void](Invoke-Tool $wc 'hg' @('init'))
    [void](Invoke-Tool $wc 'hg' @('add', '-q'))
    [void](Invoke-Tool $wc 'hg' @('commit', '-q', '-u', 'vcs1', '-m', 'base'))
    $base = Invoke-Tool $wc 'hg' @('log', '-r', '.', '--template', '{node}')
    Copy-Step 'step2' $wc
    [void](Invoke-Tool $wc 'hg' @('commit', '-q', '-u', 'vcs1', '-m', 'step2'))
    Copy-Step 'step3' $wc
    [void](Invoke-Tool $wc 'hg' @('mv', '-q', 'VcsMove.pas', 'VcsMoved.pas'))
    $tip = '.'
  }

  $ix = Invoke-Engine $wc @('index', $wc, '--db', $db)
  Check "$pTool index of the working copy" ($ix.Code -eq 0) "exit $($ix.Code)"
  $common = @('lint-all', '--db', $db, '--rule', 'unused-public-symbol', '--library-db', 'none')

  # positive control: every routine is a finding without the flag
  $all = Invoke-Engine $wc ($common + '--json')
  Check "$pTool CONTROL no flag = all six routines" ((Get-Routines $all) -eq 'Committed,Fresh,Kept,Moved,OldRoutine,Pending') (Get-Routines $all)

  $since = Invoke-Engine $wc ($common + @('--json', '--changed-since', $base))
  Check "$pTool since BASE = the committed, the pending, the untracked and the renamed" ((Get-Routines $since) -eq 'Committed,Fresh,Moved,Pending') "exit $($since.Code): $(Get-Routines $since) $($since.Err.Trim())"

  $short = Invoke-Engine $wc ($common + @('--json', '--changed-since', $base.Substring(0, 12)))
  Check "$pTool since BASE by a 12-digit id = the same" ((Get-Routines $short) -eq 'Committed,Fresh,Moved,Pending') "exit $($short.Code): $(Get-Routines $short)"

  $head = Invoke-Engine $wc ($common + @('--json', '--changed-since', $tip))
  Check "$pTool since the tip ($tip) = only what is not committed" ((Get-Routines $head) -eq 'Fresh,Moved,Pending') "exit $($head.Code): $(Get-Routines $head) $($head.Err.Trim())"

  $text = Invoke-Engine $wc ($common + @('--changed-since', $base, '--output', (Join-Path $root 'report.txt')))
  Check "$pTool text run prints the note with the counts" ($text.Out -match "--changed-since .*\($pTool [0-9a-f]{12}, working copy .*\) -- 4 of 6 finding\(s\) are on lines changed") ($text.Out -split "`n" | Select-String 'changed-since' | Out-String)
  Check "$pTool text run: the note counts the two findings on unchanged lines" ($text.Out -match 'dropped: 2 on unchanged lines, 0 outside the working copy, 0 without a file')

  $proj = Invoke-Engine $outside ($common + @('--json', '--project', (Join-Path $wc 'Vcs1.dproj'), '--changed-since', $base))
  Check "$pTool --project from a foreign folder finds the working copy" ((Get-Routines $proj) -eq 'Committed,Pending') "exit $($proj.Code): $(Get-Routines $proj) $($proj.Err.Trim())"

  $unknown = Invoke-Engine $wc ($common + @('--json', '--changed-since', 'no-such-revision-156'))
  Check "$pTool unknown revision: exit 2" ($unknown.Code -eq 2) "exit $($unknown.Code)"
  Check "$pTool unknown revision: named as such, nothing on stdout" (($unknown.Err -match 'ERROR: lint-all: --changed-since no-such-revision-156: unknown revision') -and ($unknown.Out.Trim() -eq '')) "$($unknown.Err.Trim()) | $($unknown.Out.Trim())"

  $quoted = Invoke-Engine $wc ($common + @('--json', '--changed-since', 'a\'))
  Check "$pTool a revision that cannot be passed on: exit 2, refused" (($quoted.Code -eq 2) -and ($quoted.Err -match 'is not a revision name this flag passes on')) "exit $($quoted.Code): $($quoted.Err.Trim())"

  $novcs = Invoke-Engine $outside ($common + @('--json', '--changed-since', $base))
  Check "$pTool no version control (foreign folder, no --project): exit 2 with the reason" (($novcs.Code -eq 2) -and ($novcs.Err -match 'is under no version control') -and ($novcs.Out.Trim() -eq '')) "exit $($novcs.Code): $($novcs.Err.Trim())"

  if ($pTool -eq 'hg') {
    $many = Invoke-Engine $wc ($common + @('--json', '--changed-since', 'all()'))
    Check 'hg a revset naming two changesets: exit 2, not the first one' (($many.Code -eq 2) -and ($many.Err -match 'names 2 changesets')) "exit $($many.Code): $($many.Err.Trim())"
  }

  # last: a folder that is BOTH kinds of working copy
  $other = if ($pTool -eq 'git') { '.hg' } else { '.git' }
  [void][IO.Directory]::CreateDirectory((Join-Path $wc $other))
  $both = Invoke-Engine $wc ($common + @('--json', '--changed-since', $base))
  Check "$pTool a folder with both .git and .hg: exit 2, the tool is not chosen" (($both.Code -eq 2) -and ($both.Err -match 'holds both a \.git and a \.hg')) "exit $($both.Code): $($both.Err.Trim())"
}

Write-Host '== v156 VCS-1: lint-all --changed-since ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Engine)) { Write-Host "V156 VCS1: FAIL -- engine not found: $Engine" -ForegroundColor Red; exit 1 }
if (-not (Test-Path -LiteralPath $fixture)) { Write-Host "V156 VCS1: FAIL -- fixture not found: $fixture" -ForegroundColor Red; exit 1 }
foreach ($tool in 'git', 'hg') {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { Write-Host "V156 VCS1: FAIL -- $tool is not on PATH (a missing tool is a failure, not a skip)" -ForegroundColor Red; exit 1 }
}
[void][IO.Directory]::CreateDirectory($Work)
$Work = (Get-Item -LiteralPath $Work).FullName
$parent = Test-UnderVcs $Work
if ($parent) { Write-Host "V156 VCS1: FAIL -- the scratch folder $Work is inside the working copy $parent; pass -Work <a folder under no .git / .hg>" -ForegroundColor Red; exit 1 }
try {
  Test-Tool 'git'
  Test-Tool 'hg'
} catch {
  $script:fail++
  Write-Host "  FAIL  the runner stopped: $($_.Exception.Message)" -ForegroundColor Red
} finally {
  if (-not $Keep) {
    try {
      foreach ($f in [IO.Directory]::EnumerateFiles($Work, '*', [IO.SearchOption]::AllDirectories)) { [IO.File]::SetAttributes($f, [IO.FileAttributes]::Normal) }
      [IO.Directory]::Delete($Work, $true)
    } catch { Write-Host "  note: scratch folder left behind: $Work" }
  }
}
Write-Host "SUMMARY pass=$($script:pass) fail=$($script:fail)"
if ($script:fail -gt 0) { Write-Host 'V156 VCS1: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'V156 VCS1: PASS' -ForegroundColor Green
exit 0
