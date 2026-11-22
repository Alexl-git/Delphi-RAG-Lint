<#
  WorkDirCleanup.ps1 -- v1511 HYG H01. Dot-source, then in a `finally`: Remove-WorkDir $WorkDir -Keep:$KeepWorkDir
  Removes a guard's per-run work dir (engine copies are ~100 MB each). Call AFTER the guard stopped any engine
  it started: a running exe holds the dir, so a locked delete is retried 3x (1 s apart) and then reported, never thrown.
  -Keep (the guard's -KeepWorkDir switch) leaves the dir for debugging and prints its path.
#>
function Remove-WorkDir {
  param([string] $Path, [switch] $Keep)
  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
  # 1.52.3 TESTS-ENV (c): even a kept dir never keeps the 3.4 GB platform-library copy (C: filled up on it).
  if ($Keep) {
    foreach ($lc in @(Get-ChildItem -LiteralPath $Path -Filter 'library-copy.sqlite*' -File -Recurse -ErrorAction SilentlyContinue)) { try { [IO.File]::Delete($lc.FullName) } catch { $null = $_ } }
    Write-Host "work dir kept (library-copy.sqlite removed): $Path" -ForegroundColor DarkGray; return
  }
  for ($i = 1; $i -le 3; $i++) {
    try { [IO.Directory]::Delete($Path, $true); return } catch { if ($i -lt 3) { Start-Sleep -Seconds 1 } }
  }
  Write-Host "WARNING: could not remove work dir (locked?): $Path" -ForegroundColor Yellow
}

<#
  Remove-RunnerTempDirs -- 1.52.3 TESTS-ENV (c). The battery calls it after EVERY runner (pass, fail or TIMEOUT kill):
  a runner killed on timeout never reaches its `finally`, and its drag-lint-*-<runner PID> work dir (with a 3.4 GB
  library-copy.sqlite) stayed behind. Removes %TEMP% and %LOCALAPPDATA% dirs named drag-lint-*-<pid>; a locked
  delete is skipped, never thrown. Returns the number of dirs removed.
#>
function Remove-RunnerTempDirs {
  param([Parameter(Mandatory)][int] $ProcId, [string[]] $Roots = @($env:TEMP, $env:LOCALAPPDATA))
  $n = 0
  foreach ($r in $Roots) {
    if (-not $r -or -not (Test-Path -LiteralPath $r)) { continue }
    foreach ($d in @(Get-ChildItem -LiteralPath $r -Directory -Filter ('drag-lint-*-' + $ProcId) -ErrorAction SilentlyContinue)) {
      try { [IO.Directory]::Delete($d.FullName, $true); $n++ } catch { $null = $_ }
    }
  }
  return $n
}