<#
  run_find_callees.ps1 -- TDD harness for D5 Task 9: `find-callees --qname X`
  lists the RESOLVED outgoing calls of routine X (via call_edges), the mirror
  direction of `find-callers --resolved`.

  Fixture calledfrom.pas (TAlpha.Run / TBeta.Run share the name 'Run'):
    TDispatcher.CallsAlpha -> FAlpha.Run  (FAlpha: TAlpha) resolves CERTAIN
                              to calledfrom.TAlpha.Run
    TDispatcher.CallsBeta  -> FBeta.Run   (FBeta: TBeta)   resolves CERTAIN
                              to calledfrom.TBeta.Run
    TDispatcher.CallsUnknown-> U.Run (undeclared receiver type) -> NO edge

  find-callees --qname calledfrom.TDispatcher.CallsAlpha must list exactly the
  resolved callee calledfrom.TAlpha.Run (certain), and must NOT list
  calledfrom.TBeta.Run (that's CallsBeta's callee, not CallsAlpha's).

  A routine with NO resolved outgoing calls (TAlpha.Run itself -- an empty
  body) must return an empty callee list ("0 callee(s)" / empty JSON array).

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\calledfrom.pas')).Path

# Fresh scratch dir; keep the unit name so unit-name-matches-file stays quiet.
$scratch = Join-Path C:\TEMP 'draglint_find_callees'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target  = Join-Path $scratch 'calledfrom.pas'
$db      = Join-Path $scratch 'cf.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # --- find-callees --json: CallsAlpha's resolved outgoing calls. ---
  $jsonOut = & $exePath find-callees --qname calledfrom.TDispatcher.CallsAlpha --json --db $db 2>$null | Out-String
  Check '--json: parses as JSON array' ($null -ne $jsonOut -and $jsonOut.Trim().StartsWith('['))
  $rows = $jsonOut | ConvertFrom-Json
  Check 'CallsAlpha has exactly 1 resolved callee' (@($rows).Count -eq 1)

  $target_qnames = @($rows | ForEach-Object { $_.target_qname })
  Check 'INCLUDES calledfrom.TAlpha.Run' ($target_qnames -contains 'calledfrom.TAlpha.Run')
  Check 'EXCLUDES calledfrom.TBeta.Run (that is CallsBeta''s callee, not CallsAlpha''s)' `
    (-not ($target_qnames -contains 'calledfrom.TBeta.Run'))
  Check 'callee tagged certain' (@($rows | Where-Object { $_.target_qname -eq 'calledfrom.TAlpha.Run' -and $_.confidence -eq 'certain' }).Count -eq 1)

  # --- find-callees text mode: non-empty, no crash. ---
  $txtOut = & $exePath find-callees --qname calledfrom.TDispatcher.CallsAlpha --db $db 2>$null | Out-String
  Check 'text mode: mentions the resolved callee' ($txtOut -match 'calledfrom\.TAlpha\.Run')

  # --- find-callees on a routine with NO outgoing calls (empty body). ---
  $emptyJson = & $exePath find-callees --qname calledfrom.TAlpha.Run --json --db $db 2>$null | Out-String
  $emptyRows = $emptyJson | ConvertFrom-Json
  Check 'no-callees --json: empty array' (@($emptyRows).Count -eq 0)

  $emptyTxt = & $exePath find-callees --qname calledfrom.TAlpha.Run --db $db 2>$null | Out-String
  Check 'no-callees text: "0 callee(s)"' ($emptyTxt -match '0 callee\(s\)')
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
