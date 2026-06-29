# Phase 4b (M1): cross-unit virtual-method-in-constructor. Indexes the 2-unit
# fixture, then runs `check-ast vchild.pas --db --format json` and asserts the
# store-backed check flags the call to an INHERITED virtual (VVirt, declared in
# vbase) from TVChild's constructor -- which same-file analysis cannot see -- and
# does NOT flag the non-virtual VPlain.
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$exe = Join-Path $dir '..\..\third_party\dll-win64\drag-lint.exe'
$pas = Join-Path $dir 'virtctor\vchild.pas'
$db  = Join-Path $env:TEMP ('virtctor-test-{0}.sqlite' -f $PID)

$fail = 0
function Check($name, $cond) {
  if ($cond) { Write-Host "PASS $name" }
  else { Write-Host "FAIL $name"; $script:fail++ }
}

if (Test-Path $db) { Remove-Item $db -Force }
& $exe index (Join-Path $dir 'virtctor') --db $db | Out-Null

$raw = (& $exe check-ast $pas --db $db --format json 2>$null | Out-String)
$idx = $raw.IndexOf('[')
$findings = if ($idx -ge 0) { $raw.Substring($idx) | ConvertFrom-Json } else { @() }

function Has($rule, $line) {
  return @($findings | Where-Object { $_.rule -eq $rule -and $_.start_line -eq $line }).Count -ge 1
}

Check 'fires on inherited virtual VVirt (line 23)' (Has 'virtual-method-in-constructor' 23)
Check 'does NOT fire on non-virtual VPlain (line 24)' (-not (Has 'virtual-method-in-constructor' 24))

if (Test-Path $db) { Remove-Item $db -Force -ErrorAction SilentlyContinue }
if ($fail -gt 0) { Write-Host "$fail FAILED"; exit 1 }
Write-Host 'virtctor: all pass'; exit 0
