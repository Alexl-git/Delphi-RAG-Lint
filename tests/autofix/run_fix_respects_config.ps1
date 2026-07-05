[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\gating\gating.pas')).Path

# Disable self-assignment via a local drag-lint-lint.json; leave redundant-not-not enabled.
$scratch = Join-Path C:\TEMP 'draglint_gating'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'gating.pas'
Copy-Item $fixture $target -Force
'{ "disabled": ["self-assignment"] }' | Set-Content -Path (Join-Path $scratch 'drag-lint-lint.json') -Encoding Ascii

Push-Location $scratch
try {
  $raw = & $exePath lint --file $target --fix --json --apply 2>$null | Out-String
  $arr = $null; try { $arr = ($raw | ConvertFrom-Json) } catch { $arr = $null }
  if ($null -ne $arr -and $arr -isnot [System.Array]) { $arr = @($arr) }

  $sa = $arr | Where-Object { $_.rule -eq 'self-assignment' } | Select-Object -First 1
  $nn = $arr | Where-Object { $_.rule -eq 'redundant-not-not' } | Select-Object -First 1

  Check 'disabled self-assignment NOT in fix output' ($null -eq $sa)
  Check 'enabled redundant-not-not IS in fix output'  ($null -ne $nn)

  $lines = [IO.File]::ReadAllLines($target)
  Check 'self-assignment line 12 UNCHANGED (X := X;)' ($lines[11].Trim() -eq 'X := X;')
  Check 'redundant-not-not line 14 FIXED (B := Flag;)' ($lines[13].Trim() -eq 'B := Flag;')
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
