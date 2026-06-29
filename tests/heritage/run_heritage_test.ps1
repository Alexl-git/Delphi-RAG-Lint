# Phase 1 (M1 type resolver): heritage-capture integration test.
# Indexes Heritage.pas into a throwaway DB, then asserts the parser captured
# each declared type's ancestor list into symbols.heritage (surfaced by
# `query --name <T> --json`). Exits non-zero on any failed assertion.
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$exe = Join-Path $dir '..\..\third_party\dll-win64\drag-lint.exe'
$db  = Join-Path $env:TEMP ('heritage-test-{0}.sqlite' -f $PID)

$fail = 0
function Check($name, $cond) {
  if ($cond) { Write-Host "PASS $name" }
  else { Write-Host "FAIL $name"; $script:fail++ }
}

if (Test-Path $db) { Remove-Item $db -Force }
& $exe index $dir --db $db | Out-Null

function Heritage($symName) {
  # query --json prints a non-JSON preamble (e.g. "  FTS5 probe: AVAILABLE")
  # before the array; strip everything before the first '['.
  $json = (& $exe query --name $symName --db $db --json 2>$null | Out-String)
  $idx = $json.IndexOf('[')
  if ($idx -lt 0) { return '<no-json>' }
  $obj = $json.Substring($idx) | ConvertFrom-Json
  $row = if ($obj -is [array]) { $obj | Where-Object { $_.name -eq $symName } | Select-Object -First 1 } else { $obj }
  if ($null -eq $row) { return '<no-row>' }
  if ($row.PSObject.Properties.Name -contains 'heritage') { return [string]$row.heritage }
  return '<no-field>'
}

Check 'TFoo heritage = "TBar, IBaz"' ((Heritage 'TFoo') -eq 'TBar, IBaz')
Check 'IFoo heritage = "IBar"'       ((Heritage 'IFoo') -eq 'IBar')
# No ancestors -> heritage stored NULL, so query --json omits the field.
Check 'TLone heritage empty'         ((Heritage 'TLone') -in @('', '<no-field>'))
# Verbatim capture (normalization is Phase 2's resolve pass, not capture).
Check 'TQual heritage verbatim'      ((Heritage 'TQual') -eq 'System.Classes.TComponent')
Check 'TGen heritage verbatim'       ((Heritage 'TGen')  -eq 'TBar, IList<IBaz>')

if (Test-Path $db) { Remove-Item $db -Force -ErrorAction SilentlyContinue }
if ($fail -gt 0) { Write-Host "$fail FAILED"; exit 1 }
Write-Host 'heritage: all pass'; exit 0
