<#
  run_find_callers_resolved.ps1 -- TDD harness for D5 Task 8: `query find-callers
  --resolved` emits PRECISE callers (via call_edges) instead of the noisy
  name-based list, grouped by which target symbol they actually resolved to.

  Fixture receivers.pas (TAlpha.Run / TBeta.Run / TCaller.Run, all named
  'Run') is the same D5 fixture used by Tasks 5-7. Without --resolved, `query
  find-callers --name Run` returns every ref whose text matches 'Run' -- one
  FLAT list mixing callers of all three distinct Run methods. With --resolved,
  the output GROUPS by target_qname:
    - receivers.TAlpha.Run's resolved callers: TCaller.ViaField (field FAlpha),
      TCaller.ViaParam (param AAlpha) -- both certain.
    - receivers.TBeta.Run's resolved callers: TCaller.ViaLocal (typed local B)
      -- certain.
    - receivers.TCaller.Run's resolved callers: TCaller.ViaSelf (both the
      Self.Run and bare Run call sites live in this one method) -- certain.
  The precision proof: TCaller.ViaField/ViaParam must land under
  receivers.TAlpha.Run and NOT under receivers.TBeta.Run or
  receivers.TCaller.Run (and symmetrically for ViaLocal/TBeta.Run).

  WITHOUT --resolved, the existing name-based path must be COMPLETELY
  UNCHANGED (pure additive flag): `query find-callers --name Run` still
  returns the old flat list (no grouping/confidence), non-empty.

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\receivers.pas')).Path

# Fresh scratch dir; keep the unit name so unit-name-matches-file stays quiet.
$scratch = Join-Path C:\TEMP 'draglint_findcallers_resolved'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target  = Join-Path $scratch 'receivers.pas'
$db      = Join-Path $scratch 'receivers.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # --- WITHOUT --resolved: old name-based flat list, UNCHANGED. ---
  $plainOut = & $exePath query find-callers --name Run --db $db 2>$null | Out-String
  Check 'without --resolved: still returns caller(s) (name-based, unchanged)' `
    ($plainOut -match '\d+ caller\(s\)' -and $plainOut -notmatch '\d+ caller\(0\)')
  Check 'without --resolved: no target_qname grouping marker' `
    ($plainOut -notmatch 'target_qname')
  Check 'without --resolved: no confidence tagging' `
    ($plainOut -notmatch 'certain|ambiguous')

  # --- WITH --resolved --json: grouped-by-target precision proof. ---
  $jsonOut = & $exePath query find-callers --name Run --resolved --json --db $db 2>$null | Out-String
  Check '--resolved --json: parses as JSON array' ($null -ne $jsonOut -and $jsonOut.Trim().StartsWith('['))
  $rows = $jsonOut | ConvertFrom-Json
  Check '--resolved --json: at least 4 resolved callers (Field/Param/Local/Self+bare)' ($rows.Count -ge 4)

  function CallersOf($target) { @($rows | Where-Object { $_.target_qname -eq $target }) }

  $alphaCallers = CallersOf 'receivers.TAlpha.Run'
  $betaCallers  = CallersOf 'receivers.TBeta.Run'
  $callerCallers= CallersOf 'receivers.TCaller.Run'

  Check 'TAlpha.Run has >= 2 resolved callers (field + param sites)' ($alphaCallers.Count -ge 2)
  Check 'TBeta.Run has >= 1 resolved caller (typed-local site)'      ($betaCallers.Count  -ge 1)
  Check 'TCaller.Run has >= 1 resolved caller (Self/bare site)'      ($callerCallers.Count -ge 1)

  # THE PRECISION PROOF: TCaller.ViaField / TCaller.ViaParam (the field- and
  # param-receiver call sites dispatching to TAlpha.Run) must appear under
  # TAlpha.Run's group and be ABSENT from TBeta.Run's / TCaller.Run's groups.
  Check 'ViaField lands under TAlpha.Run (not TBeta/TCaller)' `
    (($alphaCallers | Where-Object { $_.caller_qname -match 'ViaField' }).Count -ge 1 -and `
     ($betaCallers  | Where-Object { $_.caller_qname -match 'ViaField' }).Count -eq 0 -and `
     ($callerCallers| Where-Object { $_.caller_qname -match 'ViaField' }).Count -eq 0)

  Check 'ViaParam lands under TAlpha.Run (not TBeta/TCaller)' `
    (($alphaCallers | Where-Object { $_.caller_qname -match 'ViaParam' }).Count -ge 1 -and `
     ($betaCallers  | Where-Object { $_.caller_qname -match 'ViaParam' }).Count -eq 0 -and `
     ($callerCallers| Where-Object { $_.caller_qname -match 'ViaParam' }).Count -eq 0)

  # Symmetric proof: TCaller.ViaLocal (typed-local receiver -> TBeta.Run) must
  # land under TBeta.Run and be ABSENT from TAlpha.Run's / TCaller.Run's groups.
  Check 'ViaLocal lands under TBeta.Run (not TAlpha/TCaller)' `
    (($betaCallers  | Where-Object { $_.caller_qname -match 'ViaLocal' }).Count -ge 1 -and `
     ($alphaCallers | Where-Object { $_.caller_qname -match 'ViaLocal' }).Count -eq 0 -and `
     ($callerCallers| Where-Object { $_.caller_qname -match 'ViaLocal' }).Count -eq 0)

  # All rows tagged certain|ambiguous.
  $badConf = @($rows | Where-Object { $_.confidence -ne 'certain' -and $_.confidence -ne 'ambiguous' })
  Check 'every resolved caller tagged certain|ambiguous' ($badConf.Count -eq 0)

  # Every row carries the 4 required fields.
  $missingFields = @($rows | Where-Object { -not $_.caller_qname -or -not $_.file -or -not $_.target_qname -or -not $_.confidence })
  Check 'every row has caller_qname/file/confidence/target_qname' ($missingFields.Count -eq 0)
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
