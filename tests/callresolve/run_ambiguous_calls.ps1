<#
  run_ambiguous_calls.ps1 -- TDD harness for D5 Task 9: `ambiguous-calls
  [--qname X | --file F]` is the resolver-coverage diagnostic -- it lists call
  sites that NAME a known routine/method but that the resolver could NOT pin
  to a single certain target (confidence='ambiguous' in call_edges, OR no
  call_edges row at all -- untypable receiver).

  Fixture calledfrom.pas (TAlpha.Run / TBeta.Run share the name 'Run'):
    TDispatcher.CallsAlpha  -> FAlpha.Run (TAlpha) resolves CERTAIN
    TDispatcher.CallsBeta   -> FBeta.Run  (TBeta)  resolves CERTAIN
    TDispatcher.CallsUnknown-> U.Run (undeclared receiver type IUnknownThing)
                               -> NO call_edges row -> UNRESOLVED / untypable

  `ambiguous-calls --file <calledfrom.pas>` must list the CallsUnknown site
  (confidence 'unverified') and must NOT list CallsAlpha/CallsBeta (both
  resolved certain).

  `ambiguous-calls --qname calledfrom.TDispatcher.CallsAlpha` (a FULLY-resolved
  scope -- CallsAlpha's own body has only the one certain call) must return
  EMPTY (0 rows) -- "fully resolved" is a valid, exit-0 answer.

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\calledfrom.pas')).Path

# Fresh scratch dir; keep the unit name so unit-name-matches-file stays quiet.
$scratch = Join-Path C:\TEMP 'draglint_ambiguous_calls'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target  = Join-Path $scratch 'calledfrom.pas'
$db      = Join-Path $scratch 'cf.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # --- ambiguous-calls --file: whole-file coverage view. ---
  $jsonOut = & $exePath ambiguous-calls --file $target --json --db $db 2>$null | Out-String
  Check '--file --json: parses as JSON array' ($null -ne $jsonOut -and $jsonOut.Trim().StartsWith('['))
  $rows = $jsonOut | ConvertFrom-Json
  Check '--file: at least 1 ambiguous/unverified site (CallsUnknown)' (@($rows).Count -ge 1)

  $encl = @($rows | ForEach-Object { $_.enclosing_qname })
  Check 'INCLUDES CallsUnknown (untypable receiver -> unverified)' `
    ($encl -contains 'calledfrom.TDispatcher.CallsUnknown')
  Check 'EXCLUDES CallsAlpha (resolved certain)' (-not ($encl -contains 'calledfrom.TDispatcher.CallsAlpha'))
  Check 'EXCLUDES CallsBeta (resolved certain)'  (-not ($encl -contains 'calledfrom.TDispatcher.CallsBeta'))

  $unknownRow = $rows | Where-Object { $_.enclosing_qname -eq 'calledfrom.TDispatcher.CallsUnknown' } | Select-Object -First 1
  Check 'CallsUnknown tagged confidence=unverified' ($unknownRow.confidence -eq 'unverified')
  Check 'CallsUnknown row carries file' ($null -ne $unknownRow.file -and $unknownRow.file -ne '')

  # --- ambiguous-calls --file text mode. ---
  $txtOut = & $exePath ambiguous-calls --file $target --db $db 2>$null | Out-String
  Check 'text mode: mentions CallsUnknown' ($txtOut -match 'CallsUnknown')
  Check 'text mode: does not mention CallsAlpha' (-not ($txtOut -match 'CallsAlpha'))

  # --- ambiguous-calls --qname on a FULLY-resolved scope: empty, exit 0. ---
  $emptyJson = & $exePath ambiguous-calls --qname calledfrom.TDispatcher.CallsAlpha --json --db $db 2>$null | Out-String
  $emptyExit = $LASTEXITCODE
  $emptyRows = $emptyJson | ConvertFrom-Json
  Check 'fully-resolved scope --json: empty array' (@($emptyRows).Count -eq 0)
  Check 'fully-resolved scope: exit code 0 (empty is a valid answer)' ($emptyExit -eq 0)
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
