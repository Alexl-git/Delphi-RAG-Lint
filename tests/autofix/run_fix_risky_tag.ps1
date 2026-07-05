[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path
function CopyFixture($name) {
  $src = (Resolve-Path (Join-Path $PSScriptRoot "fixtures\$name")).Path
  $dir = Join-Path C:\TEMP ('draglint_risky_' + [IO.Path]::GetFileNameWithoutExtension($name))
  if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
  New-Item -ItemType Directory -Path $dir | Out-Null
  $dst = Join-Path $dir $name; Copy-Item $src $dst -Force; return $dst
}
Push-Location C:\TEMP
try {
  # risky rule -> risky:true (preview JSON)
  $t = CopyFixture 'off_by_one.pas'
  $raw = & $exePath lint --file $t --fix --fix-line 14 --fix-rule off-by-one-count --json 2>$null | Out-String
  $arr = $null; try { $arr = ($raw | ConvertFrom-Json) } catch { $arr = $null }
  if ($null -ne $arr -and $arr -isnot [System.Array]) { $arr = @($arr) }
  $o = $arr | Where-Object { $_.rule -eq 'off-by-one-count' } | Select-Object -First 1
  Check 'off-by-one-count finding present' ($null -ne $o)
  if ($null -ne $o) {
    Check 'off-by-one-count fixable=true'  ($o.fixable -eq $true)
    Check 'off-by-one-count risky=true'    ($o.risky   -eq $true)
  }

  # non-risky rule -> risky:false
  $t2 = CopyFixture 'redundant_not_not.pas'
  $raw2 = & $exePath lint --file $t2 --fix --fix-line 12 --fix-rule redundant-not-not --json 2>$null | Out-String
  $arr2 = $null; try { $arr2 = ($raw2 | ConvertFrom-Json) } catch { $arr2 = $null }
  if ($null -ne $arr2 -and $arr2 -isnot [System.Array]) { $arr2 = @($arr2) }
  $n = $arr2 | Where-Object { $_.rule -eq 'redundant-not-not' } | Select-Object -First 1
  Check 'redundant-not-not risky=false' ($null -ne $n -and $n.risky -eq $false)

  # text dry-run for the risky fix mentions [risky
  $raw3 = & $exePath lint --file $t --fix --fix-line 14 --fix-rule off-by-one-count 2>$null | Out-String
  Check 'text dry-run notes [risky' ($raw3 -match '\[risky')
} finally { Pop-Location }
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
