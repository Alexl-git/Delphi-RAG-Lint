[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path

# Apply the single fix (rule R at line L) to a fresh copy of $fixtureName and
# assert the resulting 1-based line $L, trimmed, equals $expect.
function Assert-Fix($fixtureName, $L, $R, $expect, $tag) {
  $fixture = (Resolve-Path (Join-Path $PSScriptRoot "fixtures\$fixtureName")).Path
  $scratch = Join-Path C:\TEMP ('draglint_newrules_' + [IO.Path]::GetFileNameWithoutExtension($fixtureName))
  if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
  New-Item -ItemType Directory -Path $scratch | Out-Null
  $target = Join-Path $scratch $fixtureName
  Copy-Item $fixture $target -Force
  Push-Location C:\TEMP
  try {
    $fixArgs = @('lint','--file',$target,'--fix','--fix-line',$L,'--fix-rule',$R,'--json','--apply')
    $raw = & $exePath @fixArgs 2>$null | Out-String
    $arr = $null; try { $arr = ($raw | ConvertFrom-Json) } catch { $arr = $null }
    if ($null -ne $arr -and $arr -isnot [System.Array]) { $arr = @($arr) }
    $t = $null; if ($null -ne $arr) { $t = $arr | Where-Object { $_.rule -eq $R } | Select-Object -First 1 }
    Check "${tag}: targeted finding present"    ($null -ne $t)
    if ($null -ne $t) { Check "${tag}: applied=true" ($t.applied -eq $true) }
    $lines = [IO.File]::ReadAllLines($target)
    $got = if ($lines.Count -ge $L) { $lines[$L-1].Trim() } else { '' }
    Check "${tag}: line $L => '$expect' (got '$got')" ($got -eq $expect)
  } finally { Pop-Location }
}

Assert-Fix 'redundant_not_not.pas' 12 'redundant-not-not' 'B := Flag;' '[not-not]'
Assert-Fix 'redundant_as_tobject.pas' 14 'redundant-as-tobject' 'Obj := Sender;' '[as-tobject]'
Assert-Fix 'boolean_comparison.pas' 12 'boolean-comparison-true' 'if Flag then Flag := False;'        '[bc:=True]'
Assert-Fix 'boolean_comparison.pas' 13 'boolean-comparison-true' 'if Flag then Flag := False;'        '[bc:<>False]'
Assert-Fix 'boolean_comparison.pas' 14 'boolean-comparison-true' 'if not Flag then Flag := False;'    '[bc:=False]'
Assert-Fix 'boolean_comparison.pas' 15 'boolean-comparison-true' 'if not Flag then Flag := False;'    '[bc:<>True]'
Assert-Fix 'boolean_comparison.pas' 16 'boolean-comparison-true' 'if not (A and B) then Flag := False;' '[bc:compound]'

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
