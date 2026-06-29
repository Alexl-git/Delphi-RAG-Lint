# Phase 3 (M1): ResolveTypeCategory test. Indexes typecat.pas, then asserts
# `query typecat --name <T> --json` classifies intrinsics, declared
# class/interface/enum symbols, and chases type aliases to a fixpoint.
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$exe = Join-Path $dir '..\..\third_party\dll-win64\drag-lint.exe'
$db  = Join-Path $env:TEMP ('typecat-test-{0}.sqlite' -f $PID)

$fail = 0
function Check($name, $cond) {
  if ($cond) { Write-Host "PASS $name" }
  else { Write-Host "FAIL $name"; $script:fail++ }
}

if (Test-Path $db) { Remove-Item $db -Force }
& $exe index (Join-Path $dir 'typecat.pas') --db $db | Out-Null

function Categ($typeName) {
  $raw = (& $exe query typecat --name $typeName --db $db --json 2>$null | Out-String)
  $idx = $raw.IndexOf('{')
  if ($idx -lt 0) { return '<no-json>' }
  $o = $raw.Substring($idx) | ConvertFrom-Json
  return [string]$o.category
}

# Intrinsics (resolved by name; no symbol needed).
Check 'Double -> float'   ((Categ 'Double')   -eq 'float')
Check 'Single -> float'   ((Categ 'Single')   -eq 'float')
Check 'string -> string'  ((Categ 'string')   -eq 'string')
Check 'Integer -> ordinal'((Categ 'Integer')  -eq 'ordinal')
Check 'Boolean -> boolean'((Categ 'Boolean')  -eq 'boolean')
Check 'Char -> char'      ((Categ 'Char')     -eq 'char')
Check 'Pointer -> pointer'((Categ 'Pointer')  -eq 'pointer')
Check 'PChar -> pointer'  ((Categ 'PChar')    -eq 'pointer')

# Declared symbols.
Check 'TFoo -> class'      ((Categ 'TFoo')   -eq 'class')
Check 'IFoo -> interface'  ((Categ 'IFoo')   -eq 'interface')
Check 'TColor -> enum'     ((Categ 'TColor') -eq 'enum')

# Alias chasing to fixpoint.
Check 'TMyFloat -> float (alias->intrinsic)'   ((Categ 'TMyFloat') -eq 'float')
Check 'TMyAlias -> float (alias->alias->float)'((Categ 'TMyAlias') -eq 'float')

# Unknown type.
Check 'TNoSuchType -> unknown' ((Categ 'TNoSuchType') -eq 'unknown')

if (Test-Path $db) { Remove-Item $db -Force -ErrorAction SilentlyContinue }
if ($fail -gt 0) { Write-Host "$fail FAILED"; exit 1 }
Write-Host 'typecat: all pass'; exit 0
