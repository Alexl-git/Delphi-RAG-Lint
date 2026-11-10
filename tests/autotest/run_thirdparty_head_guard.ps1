<#
  run_thirdparty_head_guard.ps1 -- build\check-thirdparty-head.ps1 (DFM-DLL-DRIFT, 2026-11-10).
  A scratch git repo with a tracked third_party\dll-win64\x.dll: clean -> exit 0; the file
  replaced (the 2026-11-09 shape: HEAD new, working tree old) -> exit 1 naming it; deleted ->
  exit 1; DRAGLINT_ALLOW_DLL_DRIFT=1 -> exit 0 with WARNING; a drifted BPL is ignored.
  POSITIVE CONTROL: the drift case MUST fail, so a check that always says OK cannot pass.
#>
$ErrorActionPreference = 'Stop'
$fail = 0
function Check([string]$n, [bool]$ok, [string]$d = '') { if ($ok) { Write-Host "PASS $n" } else { Write-Host "FAIL $n $d"; $script:fail++ } }
$script = Join-Path $PSScriptRoot '..\..\build\check-thirdparty-head.ps1'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("tph-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$dir = Join-Path $tmp 'third_party\dll-win64'
[IO.Directory]::CreateDirectory($dir) | Out-Null
function Run { $out = & pwsh -NoProfile -File $script -Root $tmp 2>&1 | Out-String; return @($LASTEXITCODE, $out) }
try {
  $null = & git -C $tmp init -q 2>&1
  $null = & git -C $tmp config user.email t@t; $null = & git -C $tmp config user.name t
  [IO.File]::WriteAllBytes("$dir\x.dll", [byte[]](1, 2, 3, 4))
  [IO.File]::WriteAllBytes("$dir\p.bpl", [byte[]](1))
  $null = & git -C $tmp add -A 2>&1; $null = & git -C $tmp commit -qm base 2>&1
  $r = Run; Check 'clean tree exits 0' ($r[0] -eq 0) $r[1]
  [IO.File]::WriteAllBytes("$dir\p.bpl", [byte[]](9, 9))
  $r = Run; Check 'drifted BPL is ignored' ($r[0] -eq 0) $r[1]
  [IO.File]::WriteAllBytes("$dir\x.dll", [byte[]](9, 9, 9))
  $r = Run
  Check 'POSITIVE CONTROL: drifted DLL exits 1' ($r[0] -eq 1) $r[1]
  Check 'drift names the file and both sizes' ($r[1] -match 'dll-win64/x\.dll\s+working=3 B\s+HEAD=4 B') $r[1]
  $env:DRAGLINT_ALLOW_DLL_DRIFT = '1'
  $r = Run; Check 'override exits 0 with WARNING' (($r[0] -eq 0) -and ($r[1] -match 'WARNING')) $r[1]
  $env:DRAGLINT_ALLOW_DLL_DRIFT = $null
  [IO.File]::Delete("$dir\x.dll")
  $r = Run; Check 'deleted DLL exits 1' ($r[0] -eq 1) $r[1]
  $r = & pwsh -NoProfile -File $script -Root ([IO.Path]::GetTempPath()) 2>&1 | Out-String
  Check 'not a work tree exits 2' ($LASTEXITCODE -eq 2) $r
} finally {
  $env:DRAGLINT_ALLOW_DLL_DRIFT = $null
  try {
    Get-ChildItem -LiteralPath $tmp -Recurse -Force -File | ForEach-Object { $_.Attributes = 'Normal' }
    [IO.Directory]::Delete($tmp, $true)
  } catch { Write-Host "note: scratch left at $tmp" }
}
if ($fail) { exit 1 }
Write-Host "ALL PASS"
