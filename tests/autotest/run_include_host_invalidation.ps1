<#
  run_include_host_invalidation.ps1 -- N-06 T9: editing ONLY an include file
  re-parses the host that took a uses clause from it on the next incremental
  index run.

  Fixture tests\fixtures\cyclefix\incuses (IncB.pas takes `uses IncA;` from
  IncB.Uses.inc).
    a. POSITIVE CONTROL: an incremental reindex with nothing changed keeps the
       IncB -> IncA include row (and reports every file up to date).
    b. rewrite ONLY IncB.Uses.inc to `uses DefA;` (newer mtime), reindex
       incrementally: IncB.pas now has an include row DefA and none for IncA.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-inc-host-inval-$PID"
)
$ErrorActionPreference = 'Stop'; $script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$inc = Join-Path $WorkDir 'incuses'; Copy-Item (Resolve-Path "$PSScriptRoot\..\fixtures\cyclefix\incuses").Path $inc -Recurse
$proj = Join-Path $inc 'IncUses.dproj'; $db = Join-Path $WorkDir 'i.sqlite'
function Index([string]$tag) {
  Push-Location $WorkDir
  try { $o = & $Exe index --project $proj --db $db --library-db none 2>&1 | Out-String } finally { Pop-Location }
  [IO.File]::WriteAllText((Join-Path $WorkDir "$tag.log"), $o)
  return $o
}
function IncRows() {
  Push-Location $WorkDir
  try { $j = & $Exe sql --db $db --query "SELECT u.unit_name FROM unit_uses u JOIN files f ON f.id = u.file_id WHERE f.path LIKE '%IncB.pas' AND u.origin_path IS NOT NULL" --json 2>$null | Out-String } finally { Pop-Location }
  try { return ,@((($j | ConvertFrom-Json).rows) | ForEach-Object { $_[0] }) } catch { return ,@() }
}

$null = Index 'first'
$r0 = IncRows
Check 'setup: IncB.pas has the include row IncA' (($r0.Count -eq 1) -and ($r0[0] -eq 'IncA')) "rows=$($r0 -join ',')"
Start-Sleep -Milliseconds 1100
$log1 = Index 'noop'
$r1 = IncRows
Check 'a: positive control: a no-change reindex keeps the IncA include row' (($r1.Count -eq 1) -and ($r1[0] -eq 'IncA')) "rows=$($r1 -join ',')"
Check 'a: positive control: the no-change reindex re-parses nothing (every file up to date)' ($log1 -match 'Done\. Files: (\d+),.*skipped \1 up-to-date') (($log1 -split "`r?`n" | Where-Object { $_ -like 'Done.*' }) -join ' ')

$incFile = Join-Path $inc 'IncB.Uses.inc'
[IO.File]::WriteAllText($incFile, "uses`r`n  DefA;`r`n", [Text.Encoding]::ASCII)
[IO.File]::SetLastWriteTime($incFile, (Get-Date).AddSeconds(5))
$log2 = Index 'after-inc-edit'
$r2 = IncRows
Check 'b: after editing only the .inc, IncB.pas has the include row DefA' (@($r2 | Where-Object { $_ -eq 'DefA' }).Count -eq 1) "rows=$($r2 -join ',')"
Check 'b: and no stale IncA include row' (@($r2 | Where-Object { $_ -eq 'IncA' }).Count -eq 0) "rows=$($r2 -join ',')"
Check 'b: exactly two files re-parsed (the .inc and its host IncB.pas)' ($log2 -match 'Done\. Files: (\d+),.*skipped (\d+) up-to-date' -and (([int]$Matches[1]) - ([int]$Matches[2]) -eq 2)) (($log2 -split "`r?`n" | Where-Object { $_ -like 'Done.*' }) -join ' ')

if ($script:Failed) { Write-Host 'run_include_host_invalidation: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_include_host_invalidation: PASS' -ForegroundColor Green; exit 0