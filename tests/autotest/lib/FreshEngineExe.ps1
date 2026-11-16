<#
  FreshEngineExe.ps1 -- v1511 HYG H02. Dot-source, then: $Exe = Get-FreshEngineExe
  Returns this tree's own Debug build (src\cli\Win64\Debug\drag-lint.exe) ONLY when it is not
  older than the newest .pas under src\ . Otherwise writes "build first / pass -Exe" and exits 2.
  Never falls back to third_party\dll-win64: a guard that reads a stale exe silently reports on
  code that is no longer in the tree. An explicit -Exe bypasses this (the caller chose it).
#>
function Get-FreshEngineExe {
  $root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
  $exe  = Join-Path $root 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path -LiteralPath $exe)) {
    Write-Host "FATAL: no build of this tree at $exe -- build first (build\build_draglint_win64.bat) or pass -Exe <path>." -ForegroundColor Red
    exit 2
  }
  $newest = Get-ChildItem -LiteralPath (Join-Path $root 'src') -Filter *.pas -File -Recurse |
    Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if ($newest -and $newest.LastWriteTimeUtc -gt (Get-Item -LiteralPath $exe).LastWriteTimeUtc) {
    Write-Host "FATAL: $exe is older than $($newest.FullName) -- build first or pass -Exe <path>. Refusing to read a stale exe." -ForegroundColor Red
    exit 2
  }
  return $exe
}
