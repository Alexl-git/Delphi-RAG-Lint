<#
  run_call_path.ps1 -- TDD harness for D5 Task 11: `call-path --from A --to B`
  prints the SHORTEST resolved call path A -> ... -> B over call_edges (BFS +
  parent-map reconstruction). "No path" is a valid answer (exit 1, message).

  Fixture callchain.pas -- a resolvable chain via typed fields:
    TChain.StepA -> TChainB.StepB -> TChainC.StepC -> TChainD.StepD
  and TLoner.Lonely, unreachable from StepA.

  call-path --from StepA --to StepD must print the full chain:
    callchain.TChain.StepA -> callchain.TChainB.StepB
      -> callchain.TChainC.StepC -> callchain.TChainD.StepD
  call-path --from StepA --to Lonely has NO path -> "no path" + exit 1.

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\callchain.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_call_path'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target  = Join-Path $scratch 'callchain.pas'
$db      = Join-Path $scratch 'cp.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # --- call-path StepA -> StepD: the full 4-node chain (text). ---
  $txt = & $exePath call-path --from StepA --to StepD --db $db 2>$null | Out-String
  $rc  = $LASTEXITCODE
  Check 'call-path A->D exit 0'                 ($rc -eq 0)
  Check 'call-path text mentions TChain.StepA'  ($txt -match 'callchain\.TChain\.StepA')
  Check 'call-path text mentions TChainB.StepB' ($txt -match 'callchain\.TChainB\.StepB')
  Check 'call-path text mentions TChainC.StepC' ($txt -match 'callchain\.TChainC\.StepC')
  Check 'call-path text mentions TChainD.StepD' ($txt -match 'callchain\.TChainD\.StepD')
  # Exact ordered chain: A -> B -> C -> D (arrow-joined, order preserved).
  $flat = ($txt -replace '\s+',' ').Trim()
  $expected = 'callchain.TChain.StepA -> callchain.TChainB.StepB -> callchain.TChainC.StepC -> callchain.TChainD.StepD'
  Check 'call-path prints EXACT ordered chain A -> B -> C -> D' ($flat -eq $expected)

  # --- call-path --json: ordered path array. ---
  $jsonOut = & $exePath call-path --from StepA --to StepD --json --db $db 2>$null | Out-String
  $obj = $jsonOut | ConvertFrom-Json
  Check 'json found:true' ($obj.found -eq $true)
  $names = @($obj.path)
  Check 'json path has 4 nodes'                 (@($names).Count -eq 4)
  Check 'json path[0] = TChain.StepA'           ($names[0] -eq 'callchain.TChain.StepA')
  Check 'json path[3] = TChainD.StepD'          ($names[3] -eq 'callchain.TChainD.StepD')

  # --- No path: StepA -> Lonely (unreachable) -> exit 1, "no path". ---
  $noTxt = & $exePath call-path --from StepA --to Lonely --db $db 2>$null | Out-String
  $noRc  = $LASTEXITCODE
  Check 'no-path exit 1'          ($noRc -eq 1)
  Check 'no-path prints "no path"' ($noTxt -match 'no path')

  $noJson = & $exePath call-path --from StepA --to Lonely --json --db $db 2>$null | Out-String
  $noObj  = $noJson | ConvertFrom-Json
  Check 'no-path json found:false' ($noObj.found -eq $false)
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
