<#
  run_cyclefix_a1_reindex.ps1 -- plan A1 (docs\superpowers\plans\2026-10-25-cycles-fix-refusal-recipes.md):
  `cycles --fix --apply` on a project whose indexed files changed on disk re-indexes it once, runs the
  plan / gate again from the current text, and applies -- instead of refusing `stale-file`.

  Every case is a copy of circular-demo, indexed, then DemoLogger.pas gets a trailing comment line
  (mtime and sha change). Needs RAD Studio: --apply builds the copy.
    main      --apply                       -> exit 0, no stale-file refusal, `reindex_before` {status ok,
                                               files >= 1} in the JSON, DemoLogger.pas edited by the plan
    CONTROL 1 dry run (no --apply)          -> exit 1, stale-file (a dry run never writes the index)
    CONTROL 2 --apply --no-reindex          -> exit 1, stale-file (the flag keeps today's refusal)
    CONTROL 3 --apply with the re-run marker DRAGLINT_CYCLEFIX_REINDEXED=1 set -> exit 1, stale-file saying
                                               "still stale after a re-index" (the second pass refuses; one retry)
    CONTROL 4 --apply on an untouched copy  -> no `reindex_before` (nothing was stale)
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-a1-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function New-Stale([string]$Tag, [bool]$Touch) {
  $d = Join-Path $WorkDir $Tag
  New-Item -ItemType Directory -Force $d | Out-Null
  Get-ChildItem (Join-Path $Repo 'circular-demo') -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $d $_.Name) -Force }
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project (Join-Path $d 'CircularDemo.dproj') --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  if ($Touch) {
    Start-Sleep -Milliseconds 1100
    [IO.File]::AppendAllText((Join-Path $d 'DemoLogger.pas'), "`r`n// edited after the index was built`r`n")
  }
  return @{ Dir = $d; Db = $db }
}
function Run-Fix($Case, [string[]]$Extra, [hashtable]$Env = @{}) {
  foreach ($k in $Env.Keys) { Set-Item "Env:$k" $Env[$k] }
  try {
    $out = (& $Exe cycles --fix --project (Join-Path $Case.Dir 'CircularDemo.dproj') --db $Case.Db --cycle 1 `
      --library-db none --format json @Extra 2>$null | Out-String)
    $code = $LASTEXITCODE
  } finally { foreach ($k in $Env.Keys) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue } }
  $j = try { $out | ConvertFrom-Json } catch { $null }
  return @{ Exit = $code; Out = $out; Json = $j }
}
function Get-Kinds($R) { if ($R.Json -and $R.Json.cycles) { return @($R.Json.cycles[0].refusals | ForEach-Object { $_.kind }) } else { return @() } }

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  Write-Host '== main: --apply on a stale index re-indexes and applies' -ForegroundColor Cyan
  $m = New-Stale 'main' $true
  $r = Run-Fix $m @('--apply')
  Check 'main exit 0' ($r.Exit -eq 0) "exit $($r.Exit) out: $($r.Out)"
  Check 'main no stale-file refusal' ((Get-Kinds $r) -notcontains 'stale-file') $r.Out
  Check 'main reindex_before.status = ok, files >= 1' ($r.Json -and $r.Json.reindex_before.status -eq 'ok' -and $r.Json.reindex_before.files -ge 1) $r.Out
  Check 'main the plan was applied (a new unit exists in the copy)' (@(Get-ChildItem $m.Dir -Filter 'DemoLogger.*.pas').Count -ge 1 -or @(Get-ChildItem $m.Dir -Filter '*Untangle*.pas').Count -ge 1 -or $r.Json.cycles[0].written -gt 0) $r.Out

  Write-Host '== controls' -ForegroundColor Cyan
  $c1 = New-Stale 'c1' $true
  $r = Run-Fix $c1 @()
  Check 'control 1 dry run: exit 1, stale-file, no reindex_before' ($r.Exit -eq 1 -and (Get-Kinds $r) -contains 'stale-file' -and -not ($r.Json -and $r.Json.reindex_before)) "exit $($r.Exit) $($r.Out)"
  $c2 = New-Stale 'c2' $true
  $r = Run-Fix $c2 @('--apply', '--no-reindex')
  Check 'control 2 --no-reindex: exit 1, stale-file' ($r.Exit -eq 1 -and (Get-Kinds $r) -contains 'stale-file') "exit $($r.Exit) $($r.Out)"
  $c3 = New-Stale 'c3' $true
  $r = Run-Fix $c3 @('--apply') @{ DRAGLINT_CYCLEFIX_REINDEXED = '1' }
  Check 'control 3 second pass: exit 1, stale-file "still stale after a re-index"' `
    ($r.Exit -eq 1 -and (Get-Kinds $r) -contains 'stale-file' -and $r.Out -match 'still stale after a re-index') "exit $($r.Exit) $($r.Out)"
  $c4 = New-Stale 'c4' $false
  $r = Run-Fix $c4 @('--apply')
  Check 'control 4 untouched copy: no reindex_before' ($r.Json -and -not $r.Json.reindex_before) "exit $($r.Exit) $($r.Out)"
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
