<#
  run_index_utc_stamps.ps1 -- lane 140-cli DST. The index stores UTC epoch seconds, derived from the
  system clock and the file's FILETIME, never from a local TDateTime round trip.

  THE DEFECT (2026-11-01, the US DST-end day): the RTL's DateTimeToUnix(Now, False) /
  TTimeZone.Local.ToUniversalTime misconverts on the transition day, so files.parsed_at came out
  now + 3600 s the WHOLE day, and a file written in the repeated 01:00-02:00 hour was stored with
  mtime_unix + 3600 (the local time is ambiguous). Four battery runners failed on it
  (run_fresh_findings, run_include_host_invalidation, run_index_inc_branch,
  run_lint_dependent_project_not_recompiled).

  Day-independent by construction: every expectation is an absolute UTC instant.
    1. parsed_at is within 120 s of the real UTC clock             (RED on the transition day)
    2. mtime_unix of a file stamped 2026-11-01 06:30:00Z equals that instant exactly   (first 01:30)
    3. mtime_unix of a file stamped 2026-11-01 07:30:00Z equals that instant exactly   (second 01:30)
    4. CONTROL: a file stamped on an ordinary day (2026-07-15 12:00:00Z) is exact
  Cases 2-3 are RED on any machine whose zone observes US DST rules; on another zone they pass,
  which is correct (no ambiguity there).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-utcstamps-$PID"
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'g8-common.ps1')
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Force $src | Out-Null
$stamps = [ordered]@{
  uA = [DateTime]::SpecifyKind([DateTime]'2026-11-01 06:30:00', 'Utc')
  uB = [DateTime]::SpecifyKind([DateTime]'2026-11-01 07:30:00', 'Utc')
  uC = [DateTime]::SpecifyKind([DateTime]'2026-07-15 12:00:00', 'Utc')
}
foreach ($n in $stamps.Keys) {
  $p = Join-Path $src "$n.pas"
  [IO.File]::WriteAllText($p, "unit $n;`r`n`r`ninterface`r`n`r`nprocedure P$n;`r`n`r`nimplementation`r`n`r`nprocedure P$n;`r`nbegin`r`nend;`r`n`r`nend.`r`n", (New-Object System.Text.ASCIIEncoding))
  [IO.File]::SetLastWriteTimeUtc($p, $stamps[$n])
}
$db = Join-Path $WorkDir 'u.sqlite'
$before = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$code = Invoke-G8Index $Exe $src $db
$after = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Check 'fixture index built' (($code -eq 0) -and (Test-Path $db)) "exit=$code"

$raw = (& $Exe sql --db $db --json --query 'SELECT path, mtime_unix, parsed_at FROM files ORDER BY path' 2>$null) -join "`n"
$j = $raw.Substring($raw.IndexOf('{')) | ConvertFrom-Json
$cols = @($j.columns | ForEach-Object { $_.name })
$rows = @($j.rows | ForEach-Object { $r = $_; $o = @{}; for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $r[$i] }; $o })
Check 'three files stored' ($rows.Count -eq 3) "rows=$($rows.Count)"
foreach ($r in $rows) {
  $leaf = [IO.Path]::GetFileNameWithoutExtension($r.path)
  $want = ([DateTimeOffset]$stamps[$leaf]).ToUnixTimeSeconds()
  Check "2-4 mtime_unix of $leaf is its exact UTC instant" ([int64]$r.mtime_unix -eq $want) "got=$($r.mtime_unix) want=$want delta=$([int64]$r.mtime_unix - $want)"
  Check "1 parsed_at of $leaf is the real UTC clock (+-120 s)" (([int64]$r.parsed_at -ge $before - 120) -and ([int64]$r.parsed_at -le $after + 120)) "got=$($r.parsed_at) clock=$before delta=$([int64]$r.parsed_at - $before)"
}
[IO.Directory]::Delete($WorkDir, $true)
if ($script:Failed) { Write-Host 'run_index_utc_stamps: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_index_utc_stamps: PASS' -ForegroundColor Green
exit 0
