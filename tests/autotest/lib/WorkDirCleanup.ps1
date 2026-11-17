<#
  WorkDirCleanup.ps1 -- v1511 HYG H01. Dot-source, then in a `finally`: Remove-WorkDir $WorkDir -Keep:$KeepWorkDir
  Removes a guard's per-run work dir (engine copies are ~100 MB each). Call AFTER the guard stopped any engine
  it started: a running exe holds the dir, so a locked delete is retried 3x (1 s apart) and then reported, never thrown.
  -Keep (the guard's -KeepWorkDir switch) leaves the dir for debugging and prints its path.
#>
function Remove-WorkDir {
  param([string] $Path, [switch] $Keep)
  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
  if ($Keep) { Write-Host "work dir kept: $Path" -ForegroundColor DarkGray; return }
  for ($i = 1; $i -le 3; $i++) {
    try { [IO.Directory]::Delete($Path, $true); return } catch { if ($i -lt 3) { Start-Sleep -Seconds 1 } }
  }
  Write-Host "WARNING: could not remove work dir (locked?): $Path" -ForegroundColor Yellow
}