[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path

# Apply every unused-local fix to a fresh copy of the fixture and compare the
# WHOLE file against .expected. A whole-file compare is the point: the defects
# this guards against (deleting a live variable that shares a declaration,
# swallowing a whole var block) show up as collateral damage ELSEWHERE in the
# file, which a per-line assertion would step right over.
$fixture  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\unused_local_shapes.pas')).Path
$expected = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\unused_local_shapes.expected')).Path
$scratch  = Join-Path C:\TEMP 'draglint_unused_local'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'unused_local_shapes.pas'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath 'lint' '--file' $target '--fix' '--fix-rule' 'unused-local' '--apply' 2>$null | Out-Null

  $got  = [IO.File]::ReadAllText($target)   -replace "`r`n", "`n"
  $want = [IO.File]::ReadAllText($expected) -replace "`r`n", "`n"
  Check 'unused-local: fixed file matches .expected' ($got -eq $want)

  if ($got -ne $want) {
    $gl = $got -split "`n"; $wl = $want -split "`n"
    for ($i = 0; $i -lt [Math]::Max($gl.Count, $wl.Count); $i++) {
      $g = if ($i -lt $gl.Count) { $gl[$i] } else { '<eof>' }
      $w = if ($i -lt $wl.Count) { $wl[$i] } else { '<eof>' }
      if ($g -ne $w) { Write-Host ("  L{0}: got '{1}' want '{2}'" -f ($i+1), $g, $w) -ForegroundColor Yellow }
    }
  }

  # The live variables must survive. These are the exact names a per-finding
  # text fix destroyed: Live shares its declaration with two dead names, and
  # Kept1/Kept2 sit above a dead tail declaration.
  foreach ($name in @('Live','Kept1','Kept2','Survivor')) {
    Check "unused-local: live variable '$name' still declared" ($got -match "(?m)^\s*$name.*:")
  }
  # ...and the dead ones must be gone from the declarations.
  foreach ($name in @('Dead1','Dead2','DeadTail','DeadHead','D1','D2','D3')) {
    Check "unused-local: dead variable '$name' removed" (-not ($got -match "(?m)^\s*$name\s*[,:]"))
  }
  # No section may be left with a bare 'var' immediately before 'begin'.
  Check 'unused-local: no orphaned var before begin' (-not ($got -match "(?m)^\s*var\s*\r?\n\s*begin"))
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
