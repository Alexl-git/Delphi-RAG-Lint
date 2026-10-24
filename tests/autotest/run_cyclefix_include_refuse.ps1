<#
  run_cyclefix_include_refuse.ps1 -- N-06 T6: cycles --fix / --plan REFUSE a
  cycle whose fix would edit a uses clause that lives in a {$I} include.

  Fixture tests\fixtures\cyclefix\includeclause: commentclause's CfAlpha with its
  implementation uses clause moved into CfAlpha.Uses.inc ({$I} at line 13).
    a. --plan text prints the refusal naming CfBeta, CfAlpha.pas, the include,
       host line 13 and the entry at CfAlpha.Uses.inc:3.
    b. the plan verdict is refused with kind uses-in-include (test dump), and
       the --fix dry run's cycle-fix/1 JSON carries the kind (exit 1).
    c. cycles --fix --apply exits 1 and leaves every source byte-identical.
    d. CONTROL: the same fixture with the include INLINED plans mechanically,
       no refusal -- so the refusal in (a)-(c) is the include, not the cycle.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-increfuse-$PID"
)
$ErrorActionPreference = 'Stop'; $script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fix = (Resolve-Path "$PSScriptRoot\..\fixtures\cyclefix\includeclause").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

function Prepare([string]$Name, [switch]$Inline) {
  $root = Join-Path $WorkDir $Name
  New-Item -ItemType Directory $root | Out-Null
  Get-ChildItem $Fix -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) }
  if ($Inline) {
    $a = Join-Path $root 'CfAlpha.pas'
    $body = [IO.File]::ReadAllText((Join-Path $root 'CfAlpha.Uses.inc')).TrimEnd("`r", "`n")
    [IO.File]::WriteAllText($a, [IO.File]::ReadAllText($a).Replace('{$I CfAlpha.Uses.inc}', $body), [Text.Encoding]::ASCII)
  }
  $db = Join-Path $WorkDir ($Name + '.sqlite')
  Push-Location $WorkDir
  try { & $Exe index --project (Join-Path $root 'IncludeClause.dproj') --db $db --library-db none *> "$db.log" } finally { Pop-Location }
  Check "$Name indexed" ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  return @{ Root = $root; Db = $db }
}
function Get-Plan([string]$Db, [string]$Tag, [string]$Format = 'text') {
  $out = Join-Path $WorkDir "$Tag-plan.$Format"; $dump = Join-Path $WorkDir "$Tag-dump.txt"
  $env:DRAGLINT_TEST_DUMP_PLAN = $dump
  try {
    $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
      -ArgumentList @('cycles', '--db', ('"' + $Db + '"'), '--edges', '--causes', '--plan', '--format', $Format, '--library-db', 'none') `
      -RedirectStandardOutput $out -RedirectStandardError "$out.err"
  } finally { $env:DRAGLINT_TEST_DUMP_PLAN = $null }
  $d = if (Test-Path $dump) { [IO.File]::ReadAllText($dump) } else { '' }
  return @{ Text = [IO.File]::ReadAllText($out); Dump = $d; Exit = $p.ExitCode }
}
function Hashes([string]$root) {
  return (Get-ChildItem $root -File | Where-Object { $_.Extension -in '.pas', '.inc', '.dpr', '.dproj' } | Sort-Object Name | ForEach-Object { $_.Name + '=' + (Get-FileHash $_.FullName -Algorithm SHA256).Hash }) -join ';'
}

$i = Prepare 'include'
$plan = Get-Plan $i.Db 'include'
$want = "refused: uses-in-include -- 'CfBeta' is used by CfAlpha.pas through {`$I CfAlpha.Uses.inc} (host line 13; entry at CfAlpha.Uses.inc:3). cycles --fix edits only a unit's own uses clause; edit CfAlpha.Uses.inc by hand, or inline the clause into CfAlpha.pas and reindex."
Check 'a: --plan prints the uses-in-include refusal text' ($plan.Text.Contains($want)) ''
Check 'b: verdict refused' ($plan.Dump -match 'verdict=refused') $plan.Dump.Trim()
Check 'b: refusal kind uses-in-include' ($plan.Dump -match 'refusals=[^\t]*\buses-in-include\b') $plan.Dump.Trim()
$dproj = Join-Path $i.Root 'IncludeClause.dproj'
Push-Location $WorkDir
try { $dry = & $Exe cycles --fix --project $dproj --db $i.Db --unit cfalpha --no-compile --format json --library-db none 2>$null | Out-String; $dryRc = $LASTEXITCODE } finally { Pop-Location }
Check 'b: --fix dry run exits 1 (refused)' ($dryRc -eq 1) "rc=$dryRc"
$ref = @(); try { $ref = @(($dry | ConvertFrom-Json).cycles | ForEach-Object { $_.refusals } | Where-Object { $_.kind -eq 'uses-in-include' }) } catch { }
Check 'b: the cycle-fix/1 JSON has a uses-in-include refusal at CfAlpha.pas line 13' (($ref.Count -eq 1) -and ($ref[0].line -eq 13) -and ($ref[0].file -like '*CfAlpha.pas')) "n=$($ref.Count)"

$before = Hashes $i.Root
Push-Location $WorkDir
try { $fx = & $Exe cycles --fix --project $dproj --db $i.Db --unit cfalpha --apply --library-db none 2>&1 | Out-String; $fxRc = $LASTEXITCODE } finally { Pop-Location }
Check 'c: cycles --fix --apply exits 1 (refused)' ($fxRc -eq 1) "rc=$fxRc"
Check 'c: cycles --fix --apply names uses-in-include' ($fx -match 'uses-in-include') ''
Check 'c: every source byte-identical after --apply' ((Hashes $i.Root) -eq $before) ''

$c = Prepare 'inlined' -Inline
$cp = Get-Plan $c.Db 'inlined'
Check 'd: control (inlined): verdict mechanical' ($cp.Dump -match 'verdict=mechanical') $cp.Dump.Trim()
Check 'd: control (inlined): no uses-in-include' ($cp.Text -notmatch 'uses-in-include') ''

if ($script:Failed) { Write-Host 'run_cyclefix_include_refuse: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_cyclefix_include_refuse: PASS' -ForegroundColor Green; exit 0