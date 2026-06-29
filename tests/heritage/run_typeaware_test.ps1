# Phase 4 (M1): store-path type-aware rules. Indexes tc_store.pas, then runs
# `check-ast <file> --db <db> --format json` (a store-bearing path) and asserts
# the resolver's exact behavior where it diverges from the name heuristic:
#   - float-equality fires on an alias-to-Double comparison (heuristic misses)
#   - freeandnil-on-interface fires on a non-I-prefixed interface (heuristic misses)
#   - freeandnil-on-interface is SUPPRESSED on an I-prefixed CLASS (heuristic FPs)
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$exe = Join-Path $dir '..\..\third_party\dll-win64\drag-lint.exe'
$pas = Join-Path $dir 'typeaware\tc_store.pas'
$db  = Join-Path $env:TEMP ('typeaware-test-{0}.sqlite' -f $PID)

$fail = 0
function Check($name, $cond) {
  if ($cond) { Write-Host "PASS $name" }
  else { Write-Host "FAIL $name"; $script:fail++ }
}

if (Test-Path $db) { Remove-Item $db -Force }
& $exe index (Join-Path $dir 'typeaware') --db $db | Out-Null

$raw = (& $exe check-ast $pas --db $db --format json 2>$null | Out-String)
$idx = $raw.IndexOf('[')
$findings = if ($idx -ge 0) { $raw.Substring($idx) | ConvertFrom-Json } else { @() }

function Has($rule, $line) {
  return @($findings | Where-Object { $_.rule -eq $rule -and $_.start_line -eq $line }).Count -ge 1
}

Check 'float-equality fires on alias-to-Double (line 30)' (Has 'float-equality-comparison' 30)
Check 'freeandnil fires on non-I-prefix interface (line 31)' (Has 'freeandnil-on-interface' 31)
Check 'freeandnil SUPPRESSED on I-prefix class (line 32)' (-not (Has 'freeandnil-on-interface' 32))

# string-equality store-path (se_store.pas): integer '=' suppressed, string '=' fires.
$rawSE = (& $exe check-ast (Join-Path $dir 'typeaware\se_store.pas') --db $db --format json 2>$null | Out-String)
$idxSE = $rawSE.IndexOf('[')
$findingsSE = if ($idxSE -ge 0) { $rawSE.Substring($idxSE) | ConvertFrom-Json } else { @() }
function HasSE($line) { return @($findingsSE | Where-Object { $_.rule -eq 'string-equality-comparison' -and $_.start_line -eq $line }).Count -ge 1 }
Check 'string-equality NOT on integer = (line 18)' (-not (HasSE 18))
Check 'string-equality fires on string = (line 19)' (HasSE 19)

if (Test-Path $db) { Remove-Item $db -Force -ErrorAction SilentlyContinue }
if ($fail -gt 0) { Write-Host "$fail FAILED"; exit 1 }
Write-Host 'typeaware: all pass'; exit 0
