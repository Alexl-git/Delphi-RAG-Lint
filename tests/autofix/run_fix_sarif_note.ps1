[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\redundant_not_not.pas')).Path
$scratch = Join-Path C:\TEMP 'draglint_sarifnote'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'redundant_not_not.pas'
Copy-Item $fixture $target -Force
Push-Location C:\TEMP
try {
  $errFile = Join-Path $scratch 'err.txt'
  $outFile = Join-Path $scratch 'out.txt'
  Start-Process -FilePath $exePath -ArgumentList @('lint','--file',$target,'--fix','--format','sarif') `
    -NoNewWindow -Wait -RedirectStandardError $errFile -RedirectStandardOutput $outFile
  $err = Get-Content $errFile -Raw
  $out = Get-Content $outFile -Raw
  Check 'stderr mentions SARIF-not-supported note' ($err -match 'sarif' -and $err -match 'text')
  Check 'stdout is NOT sarif json ($schema absent)' (-not ($out -match '\$schema'))
} finally { Pop-Location }
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
