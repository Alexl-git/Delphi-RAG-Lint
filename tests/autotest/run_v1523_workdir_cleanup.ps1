<#
  run_v1523_workdir_cleanup.ps1 -- 1.52.3 TESTS-ENV (c): runners must not leave the 3.4 GB library-copy.sqlite behind.
    W1 Remove-WorkDir -Keep removes library-copy.sqlite but keeps the rest of the dir
    W2 Remove-WorkDir (no -Keep) removes the whole dir
    W3 Remove-RunnerTempDirs removes drag-lint-*-<pid> (with its library-copy.sqlite) and leaves other pids alone
    W4 a real runner (run_cyclefix_dryrun.ps1) leaves no NEW library-copy.sqlite under %TEMP%\drag-lint-*
  pwsh -File tests\autotest\run_v1523_workdir_cleanup.ps1 [-Exe <drag-lint.exe>] [-SkipRunner]
#>
[CmdletBinding()]
param([string]$Exe = '', [switch]$SkipRunner)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
. "$PSScriptRoot\lib\WorkDirCleanup.ps1"
$script:Fail = 0
function Check([string]$n, [bool]$ok, [string]$d = '') {
  if ($ok) { Write-Host "[PASS] $n" -ForegroundColor Green } else { $script:Fail++; Write-Host "[FAIL] $n  $d" -ForegroundColor Red }
}
function New-Planted([string]$Path) {
  [IO.Directory]::CreateDirectory($Path) | Out-Null
  [IO.File]::WriteAllText((Join-Path $Path 'library-copy.sqlite'), 'x')
  [IO.File]::WriteAllText((Join-Path $Path 'notes.txt'), 'n')
}
$Base = Join-Path ([IO.Path]::GetTempPath()) ('dl-v1523-wdc-' + [guid]::NewGuid().ToString('N'))
$fake = 2000000000 + (Get-Random -Maximum 99999)
try {
  $k = Join-Path $Base 'keep'; New-Planted $k
  Remove-WorkDir $k -Keep
  Check 'W1 -Keep drops library-copy.sqlite, keeps the rest' ((-not (Test-Path (Join-Path $k 'library-copy.sqlite'))) -and (Test-Path (Join-Path $k 'notes.txt')))
  $d = Join-Path $Base 'del'; New-Planted $d
  Remove-WorkDir $d
  Check 'W2 plain Remove-WorkDir removes the dir' (-not (Test-Path $d))
  $mine = Join-Path $Base "drag-lint-cyclefix-x-$fake"; $other = Join-Path $Base "drag-lint-cyclefix-x-$($fake + 1)"
  New-Planted $mine; New-Planted $other
  $n = Remove-RunnerTempDirs -ProcId $fake -Roots @($Base)
  Check 'W3 sweep removes the dead runner pid dir (count 1), not another pid' (($n -eq 1) -and (-not (Test-Path $mine)) -and (Test-Path $other)) "n=$n"
} finally {
  Remove-WorkDir $Base
}
if (-not $SkipRunner) {
  $lib = 'C:\Projects\.drag-lint\library-Win64.sqlite'
  $before = @(Get-ChildItem -Path ([IO.Path]::GetTempPath()) -Directory -Filter 'drag-lint-*' -ErrorAction SilentlyContinue | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Filter 'library-copy.sqlite' -ErrorAction SilentlyContinue } | ForEach-Object { $_.FullName })
  $out = & pwsh -NoProfile -File "$PSScriptRoot\run_cyclefix_dryrun.ps1" -Exe $Exe 2>&1 | Out-String
  $after = @(Get-ChildItem -Path ([IO.Path]::GetTempPath()) -Directory -Filter 'drag-lint-*' -ErrorAction SilentlyContinue | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Filter 'library-copy.sqlite' -ErrorAction SilentlyContinue } | ForEach-Object { $_.FullName })
  $new = @($after | Where-Object { $before -notcontains $_ })
  Check 'W4 real runner ran (PASS or SKIP) and left no new library-copy.sqlite' (($LASTEXITCODE -eq 0) -and ($new.Count -eq 0)) ("exit=$LASTEXITCODE new=" + ($new -join ';'))
}
if ($script:Fail) { Write-Host "FAILED: $script:Fail" -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green; exit 0