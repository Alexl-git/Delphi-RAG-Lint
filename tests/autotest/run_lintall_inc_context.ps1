<#
  run_lintall_inc_context.ps1 -- lane INC2 (2026-10-27): lint-all lints a
  project's include files, parsed from the same bytes the indexer parsed (the
  includer's define context), with positions on the include's own lines and one
  finding per include however many units include it.

  Fixture tests\fixtures\inc_lint (copied to a scratch dir per run):
    app\U1.pas, app\U2.pas   both {$DEFINE HOSTON} {$I Body.inc}
    app\Body.inc             {$IFDEF HOSTON} empty except on line 7
                             {$ELSE}         empty except on line 15 {$ENDIF}

  Checks: lint-all reports empty-except in Body.inc on line 7 exactly once
  (two includers, one finding); line 15 (the branch the hosts never compile)
  is not reported; positive control: plain `lint Body.inc` (standalone, no
  host) reports line 15, so the context is what moved the finding.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lintall-inc-$PID"
)
$ErrorActionPreference = 'Stop'; $script:Failed = $false; $script:Passed = 0; $script:FailedN = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:Failed = $true; $script:FailedN++ }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
try {
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$fx = Join-Path $WorkDir 'inc_lint'
Copy-Item (Resolve-Path "$PSScriptRoot\..\fixtures\inc_lint").Path $fx -Recurse
$proj = Join-Path $fx 'app\LintInc.dproj'
$body = Join-Path $fx 'app\Body.inc'
$db   = Join-Path $WorkDir 'l.sqlite'

function RunJson([string[]]$argv, [string]$tag) {
  Push-Location $WorkDir
  try { $o = & $Exe @argv 2> (Join-Path $WorkDir "$tag.err") | Out-String } finally { Pop-Location }
  [IO.File]::WriteAllText((Join-Path $WorkDir "$tag.json"), $o)
  # lint / lint-all --json: a bare ARRAY of findings with start_line (see
  # feedback_lint_json_is_an_array_with_start_line).
  try { return ,@($o | ConvertFrom-Json) } catch { return ,@() }
}
function BodyHits($findings, [string]$rule) {
  return ,@($findings | Where-Object { ($_.rule -eq $rule) -and ([IO.Path]::GetFileName([string]$_.file_path) -ieq 'Body.inc') })
}

Push-Location $WorkDir
try { $null = & $Exe index --project $proj --db $db --library-db none 2>&1 } finally { Pop-Location }

$all = RunJson @('lint-all', '--db', $db, '--project', $proj, '--json') 'lintall'
$hits = BodyHits $all 'empty-except'
$lines = @($hits | ForEach-Object { [int]$_.start_line })
Write-Host ("  lint-all findings: {0} total, Body.inc empty-except lines: {1}" -f $all.Count, ($lines -join ','))
Check 'lint-all: Body.inc is scanned (empty-except found in it)' ($hits.Count -ge 1)
Check 'lint-all: exactly ONE empty-except in Body.inc (two includers, no duplicate)' ($hits.Count -eq 1) "n=$($hits.Count)"
Check 'lint-all: it is on Body.inc line 7 (the HOSTON branch the includers compile)' (($lines.Count -ge 1) -and ($lines[0] -eq 7)) "got=$($lines -join ',')"
Check 'lint-all: line 15 (the branch no includer compiles) is NOT reported' (-not ($lines -contains 15))
$err = [IO.File]::ReadAllText((Join-Path $WorkDir 'lintall.err'))
Check 'lint-all: the banner counts the include file' ($err -match 'scanning 4 ') (($err -split "`r?`n" | Where-Object { $_ -match 'scanning' }) -join ' ')

# Positive control: standalone `lint` (no includer context) takes the ELSE branch.
$one = RunJson @('lint', $body, '--db', $db, '--json') 'lintone'
$oneLines = @((BodyHits $one 'empty-except') | ForEach-Object { [int]$_.start_line })
Check 'control: standalone lint Body.inc reports line 15 (no host define)' ($oneLines -contains 15) "got=$($oneLines -join ',')"
} finally {
  Write-Host ''
  Write-Host ("RESULT: {0} passed, {1} failed" -f $script:Passed, $script:FailedN)
}
if ($script:Failed) { exit 1 } else { exit 0 }
