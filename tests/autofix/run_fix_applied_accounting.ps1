[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\redundant_not_not.pas')).Path
$scratch = Join-Path C:\TEMP "draglint_applied_$PID"
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
  # Target a NON-fixable finding (used-before-assignment on gating.pas line 12 -- write-only-local,
  # the old control, is fixable since autofix lane A3) with --apply: it is in Targeted (rule
  # filter off), fixable=false, and applied must be false (no edit).
  $target3 = Join-Path $scratch 'gating.pas'
  Copy-Item (Join-Path $PSScriptRoot 'fixtures\gating\gating.pas') $target3 -Force
  $raw3 = & $exePath lint --file $target3 --fix --fix-line 12 --json --apply 2>$null | Out-String
  $arr3 = $null; try { $arr3 = ($raw3 | ConvertFrom-Json) } catch { $arr3 = $null }
  if ($null -ne $arr3 -and $arr3 -isnot [System.Array]) { $arr3 = @($arr3) }
  $t3 = $arr3 | Where-Object { $_.rule -eq 'used-before-assignment' } | Select-Object -First 1
  Check 'no-edit: non-fixable finding present' ($null -ne $t3)
  if ($null -ne $t3) {
    Check 'no-edit: fixable=false'          ($t3.fixable -eq $false)
    Check 'no-edit: applied=false (no edit)' ($t3.applied -eq $false)
  }

  # OFF-LINE EDITS (lane DIRLINT, 2026-10-27): a fix whose edits are ALL away from
  # the finding's line -- field-created-not-freed inserts FreeAndNil before
  # `inherited` in the destructor and adds System.SysUtils to a uses clause --
  # must still report applied=true. The row used to be matched to an edit by
  # (file, StartLine), so such a fixer reported applied=false while the file
  # changed, and lanes padded fixers with identity edits on the finding's span.
  $dtorSrc = Join-Path $PSScriptRoot 'fixtures\field-created-not-freed\dtor.pas'
  $dtor    = Join-Path $scratch 'dtor.pas'
  $dtorTxt = [IO.File]::ReadAllText($dtorSrc).Replace("implementation`r`n`r`nuses`r`n  System.SysUtils;`r`n", "implementation`r`n")
  [IO.File]::WriteAllText($dtor, $dtorTxt, [Text.Encoding]::ASCII)
  Check 'off-line: fixture has no System.SysUtils' (-not $dtorTxt.Contains('System.SysUtils'))
  $raw4 = & $exePath lint --file $dtor --fix --fix-rule field-created-not-freed --json --apply --no-backup 2>$null | Out-String
  $arr4 = $null; try { $arr4 = @($raw4 | ConvertFrom-Json) } catch { $arr4 = $null }
  $t4 = $arr4 | Where-Object { $_.rule -eq 'field-created-not-freed' } | Select-Object -First 1
  Check 'off-line: finding present' ($null -ne $t4)
  $after = [IO.File]::ReadAllText($dtor)
  Check 'off-line: FreeAndNil inserted'        ($after.Contains('FreeAndNil(FX);'))
  Check 'off-line: System.SysUtils added'      ($after.Contains('System.SysUtils'))
  if ($null -ne $t4) { Check 'off-line: applied=true' ($t4.applied -eq $true) }

  # The fixes that edit ABOVE (or around) the finding's line (lane A3 + A5 + G4):
  # each must report applied=true on its own fixture AND change the file.
  foreach ($id in @('create-inside-try', 'field-by-name-in-loop', 'swap-without-temp', 'unprotected-object-free',
                    'doc-orphan-block', 'begin-end-pair-not-in-finally')) {
    $fx = Get-ChildItem (Join-Path $PSScriptRoot "fixtures\$id") -Filter '*.pas' | Where-Object { $_.Name -notlike '*.fixed.pas' } | Select-Object -First 1
    if ($null -eq $fx) { Check "off-line ${id}: fixture present" $false; continue }
    $tgt = Join-Path $scratch "$id-$($fx.Name)"
    Copy-Item $fx.FullName $tgt -Force
    $before = [IO.File]::ReadAllText($tgt)
    $rawX = & $exePath lint --file $tgt --fix --fix-rule $id --json --apply --no-backup 2>$null | Out-String
    $arrX = $null; try { $arrX = @($rawX | ConvertFrom-Json) } catch { $arrX = $null }
    $appX = @($arrX | Where-Object { $_.rule -eq $id -and $_.applied -eq $true })
    Check "off-line ${id}: applied=true and the file changed" (($appX.Count -ge 1) -and ([IO.File]::ReadAllText($tgt) -ne $before))
  }
} finally { Pop-Location }
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_applied_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
