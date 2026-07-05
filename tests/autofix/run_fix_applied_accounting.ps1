[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\redundant_not_not.pas')).Path
$scratch = Join-Path C:\TEMP 'draglint_applied'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'redundant_not_not.pas'

Push-Location C:\TEMP
try {
  # PREVIEW (no --apply): a fixable finding that WOULD produce an edit reports
  # applied=false, preview=true.
  Copy-Item $fixture $target -Force
  $raw = & $exePath lint --file $target --fix --fix-line 12 --fix-rule redundant-not-not --json 2>$null | Out-String
  $arr = $null; try { $arr = ($raw | ConvertFrom-Json) } catch { $arr = $null }
  if ($null -ne $arr -and $arr -isnot [System.Array]) { $arr = @($arr) }
  $t = $arr | Where-Object { $_.rule -eq 'redundant-not-not' } | Select-Object -First 1
  Check 'preview: finding present'  ($null -ne $t)
  if ($null -ne $t) {
    Check 'preview: fixable=true'  ($t.fixable -eq $true)
    Check 'preview: applied=false' ($t.applied -eq $false)
    Check 'preview: preview=true'  ($t.preview -eq $true)
  }

  # APPLY: a fixable finding that DID produce an edit reports applied=true.
  Copy-Item $fixture $target -Force
  $raw2 = & $exePath lint --file $target --fix --fix-line 12 --fix-rule redundant-not-not --json --apply 2>$null | Out-String
  $arr2 = $null; try { $arr2 = ($raw2 | ConvertFrom-Json) } catch { $arr2 = $null }
  if ($null -ne $arr2 -and $arr2 -isnot [System.Array]) { $arr2 = @($arr2) }
  $t2 = $arr2 | Where-Object { $_.rule -eq 'redundant-not-not' } | Select-Object -First 1
  if ($null -ne $t2) {
    Check 'apply: applied=true'  ($t2.applied -eq $true)
    Check 'apply: preview=false' ($t2.preview -eq $false)
  }

  # NO-EDIT: a fixable RULE targeted where the finding is filtered out (wrong line)
  # produces no edit -> the finding is not in Targeted, so it is simply absent.
  # The invariant we lock: applied is never true for a finding that produced no edit.
  # Target a NON-fixable finding (write-only-local at line 9) with --apply: it is in
  # Targeted (rule filter off), fixable=false, and applied must be false (no edit).
  Copy-Item $fixture $target -Force
  $raw3 = & $exePath lint --file $target --fix --fix-line 9 --json --apply 2>$null | Out-String
  $arr3 = $null; try { $arr3 = ($raw3 | ConvertFrom-Json) } catch { $arr3 = $null }
  if ($null -ne $arr3 -and $arr3 -isnot [System.Array]) { $arr3 = @($arr3) }
  $t3 = $arr3 | Where-Object { $_.rule -eq 'write-only-local' } | Select-Object -First 1
  Check 'no-edit: non-fixable finding present' ($null -ne $t3)
  if ($null -ne $t3) {
    Check 'no-edit: fixable=false'          ($t3.fixable -eq $false)
    Check 'no-edit: applied=false (no edit)' ($t3.applied -eq $false)
  }
} finally { Pop-Location }
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
