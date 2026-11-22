<#
  run_v1523_hermetic_selfheal.ps1 -- 1.52.3 TESTS-ENV (a): Get-HermeticEngine heals an INCOMPLETE cache entry.
  A cached entry whose exe survived but whose companions (sqlite3.dll, tree-sitter*.dll, castlib) are gone
  makes the exe die 0xC0000135 and the runners print only "index failed". The helper must copy back every
  companion the source dir has and the entry lacks.
    H1 control: a fresh entry holds every companion of the source dir
    H2 plant: delete sqlite3.dll + tree-sitter.dll + one rules\ file from the entry, call again -> all three are back
    H3 the healed call returns the same exe path (no new key)
    H4 a complete entry is returned untouched (a marker file added to it survives)
  Uses a fake engine dir (no real engine is run).   pwsh -File tests\autotest\run_v1523_hermetic_selfheal.ps1 [-Lib <HermeticEngine.ps1>]
#>
[CmdletBinding()]
param([string]$Lib = '')
if (-not $Lib) { $Lib = "$PSScriptRoot\lib\HermeticEngine.ps1" }
. $Lib
$ErrorActionPreference = 'Continue'
$script:Fail = 0
function Check([string]$n, [bool]$ok, [string]$d = '') {
  if ($ok) { Write-Host "[PASS] $n" -ForegroundColor Green } else { $script:Fail++; Write-Host "[FAIL] $n  $d" -ForegroundColor Red }
}
$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v1523-heal-' + [guid]::NewGuid().ToString('N'))
$Eng = Join-Path $Work 'engine'
[IO.Directory]::CreateDirectory((Join-Path $Eng 'rules')) | Out-Null
$rnd = New-Object Random
$bytes = New-Object byte[] (1000 + $rnd.Next(5000)); $rnd.NextBytes($bytes)   # unique size -> unique cache key
[IO.File]::WriteAllBytes((Join-Path $Eng 'drag-lint.exe'), $bytes)
foreach ($n in 'sqlite3.dll', 'tree-sitter.dll', 'tree-sitter-delphi13.dll', 'casts.castlib') { [IO.File]::WriteAllText((Join-Path $Eng $n), 'x') }
[IO.File]::WriteAllText((Join-Path $Eng 'rules\a.scm'), '; r'); [IO.File]::WriteAllText((Join-Path $Eng 'rules\b.scm'), '; r')
[IO.File]::WriteAllText((Join-Path $Eng 'drag-lint.json'), '{}')
$dest = ''
try {
  $h = Get-HermeticEngine (Join-Path $Eng 'drag-lint.exe')
  $dest = Split-Path -Parent $h
  $miss = @('sqlite3.dll', 'tree-sitter.dll', 'tree-sitter-delphi13.dll', 'casts.castlib', 'rules\a.scm') | Where-Object { -not (Test-Path -LiteralPath (Join-Path $dest $_)) }
  Check 'H1 fresh entry is complete' ($miss.Count -eq 0) ("missing=" + ($miss -join ','))
  [IO.File]::Delete((Join-Path $dest 'sqlite3.dll')); [IO.File]::Delete((Join-Path $dest 'tree-sitter.dll'))
  [IO.File]::Delete((Join-Path $dest 'rules\a.scm'))   # PARTIAL rules\ dir (the real 238 -> 10 case)
  $h2 = Get-HermeticEngine (Join-Path $Eng 'drag-lint.exe')
  $miss = @('sqlite3.dll', 'tree-sitter.dll', 'rules\a.scm') | Where-Object { -not (Test-Path -LiteralPath (Join-Path $dest $_)) }
  Check 'H2 planted incomplete entry is healed' ($miss.Count -eq 0) ("still missing=" + ($miss -join ','))
  Check 'H3 healed call returns the same exe path' ($h2 -eq $h) "$h2 vs $h"
  [IO.File]::WriteAllText((Join-Path $dest 'marker.txt'), 'm')
  $null = Get-HermeticEngine (Join-Path $Eng 'drag-lint.exe')
  Check 'H4 complete entry untouched' (Test-Path -LiteralPath (Join-Path $dest 'marker.txt'))
} finally {
  foreach ($d in $dest, $Work) { if ($d -and (Test-Path -LiteralPath $d)) { try { [IO.Directory]::Delete($d, $true) } catch { $null = $_ } } }
}
if ($script:Fail) { Write-Host "FAILED: $script:Fail" -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green; exit 0