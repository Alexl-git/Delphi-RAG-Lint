<#
  run_doc_p2_store.ps1 -- Auto-Document Phase 2, Task 1: symbol_facts storage
  plumbing (TSymbolFacts record + ISymbolStore.GetSymbolFacts/PutSymbolFacts).

  Exercises the hidden `doc-facts-selftest --db <db>` verb: it looks up the
  real symbol_id of ComputeTotal (fixtures\docp2store\p2store.pas), Puts a
  known TSymbolFacts row (ReturnsOwner='new', Cyclomatic=14, plus CSV
  ReadsFields/WritesFields built via the Doc.SymbolFacts CSV helpers), then
  Gets it back and prints the round-trip. Also probes GetSymbolFacts on a
  symbol_id with no row -> Present=False (ABSENT_PRESENT=0).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
$script:Failed = $false

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp2store\p2store.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docp2store'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'p2store.pas'
$db     = Join-Path $scratch 'docp2store.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  $out = & $exePath doc-facts-selftest --db $db 2>$null
  $exitCode = $LASTEXITCODE
  $raw = ($out -join "`n")

  Check 'doc-facts-selftest exits 0' ($exitCode -eq 0)

  $rt  = [regex]::Match($raw, 'RT=(\S+) CYC=(\S+)')
  Check 'RT=/CYC= line present' ($rt.Success)
  if ($rt.Success) {
    Check 'RT round-tripped as ''new''' ($rt.Groups[1].Value -eq 'new')
    Check 'CYC round-tripped as 14'     ($rt.Groups[2].Value -eq '14')
  }

  $reads  = [regex]::Match($raw, 'READS=(\S+)')
  $writes = [regex]::Match($raw, 'WRITES=(\S+)')
  Check 'READS round-tripped (CSV via SymbolFactsCsvJoin)'  ($reads.Success  -and $reads.Groups[1].Value  -eq 'FName,FAge')
  Check 'WRITES round-tripped (CSV via SymbolFactsCsvJoin)' ($writes.Success -and $writes.Groups[1].Value -eq 'FBalance')

  $present = [regex]::Match($raw, 'PRESENT=(\d)')
  Check 'PRESENT=1 for the row just written' ($present.Success -and $present.Groups[1].Value -eq '1')

  $absent = [regex]::Match($raw, 'ABSENT_PRESENT=(\d)')
  Check 'ABSENT_PRESENT=0 for a symbol_id with no symbol_facts row' ($absent.Success -and $absent.Groups[1].Value -eq '0')
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
