# Phase 2 (M1): cross-unit ancestry resolution test. Indexes the two-unit
# ancestry fixture, then asserts `query ancestors --name <T> --json` returns the
# transitive, cross-unit-resolved ancestor closure (the IsDescendantOf surface).
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$exe = Join-Path $dir '..\..\third_party\dll-win64\drag-lint.exe'
$db  = Join-Path $env:TEMP ('ancestry-test-{0}.sqlite' -f $PID)

$fail = 0
function Check($name, $cond) {
  if ($cond) { Write-Host "PASS $name" }
  else { Write-Host "FAIL $name"; $script:fail++ }
}

if (Test-Path $db) { Remove-Item $db -Force }
& $exe index (Join-Path $dir 'ancestry') --db $db | Out-Null

# Returns the transitive ancestor objects for $symName (name + kind + resolved).
function Ancestors($symName) {
  $raw = (& $exe query ancestors --name $symName --db $db --json 2>$null | Out-String)
  $idx = $raw.IndexOf('{')
  if ($idx -lt 0) { return $null }
  return ($raw.Substring($idx) | ConvertFrom-Json)
}

function AncestorNames($symName) {
  $o = Ancestors $symName
  if ($null -eq $o -or $null -eq $o.ancestors) { return @() }
  return @($o.ancestors | ForEach-Object { $_.name })
}

$tchild = AncestorNames 'TChild'
Check 'TChild ancestors include TBase'  ($tchild -contains 'TBase')
Check 'TChild ancestors include TGrand (transitive, cross-unit)' ($tchild -contains 'TGrand')
Check 'TChild ancestors include IBase (implemented iface)' ($tchild -contains 'IBase')

$ichild = AncestorNames 'IChild'
Check 'IChild ancestors include IBase (cross-unit iface parent)' ($ichild -contains 'IBase')

# Resolved cross-unit: TBase must carry kind=class and resolved=true.
$tbase = (Ancestors 'TChild').ancestors | Where-Object { $_.name -eq 'TBase' } | Select-Object -First 1
Check 'TBase edge resolved to a class symbol' ($null -ne $tbase -and $tbase.kind -eq 'class' -and $tbase.resolved)

# TGrand has no ancestors -> empty closure.
$tgrand = AncestorNames 'TGrand'
Check 'TGrand has no ancestors' ($tgrand.Count -eq 0)

# IsDescendantOf / ImplementsInterface via `--of`.
function OfCheck($name, $of) {
  $raw = (& $exe query ancestors --name $name --of $of --db $db --json 2>$null | Out-String)
  $idx = $raw.IndexOf('{'); if ($idx -lt 0) { return $null }
  return ($raw.Substring($idx) | ConvertFrom-Json)
}
$o1 = OfCheck 'TChild' 'TGrand'
Check 'TChild descends TGrand (class chain)' ($o1.is_descendant -and -not $o1.implements)
$o2 = OfCheck 'TChild' 'IBase'
Check 'TChild implements IBase (interface)' ($o2.is_descendant -and $o2.implements)
$o3 = OfCheck 'TChild' 'TUnrelated'
Check 'TChild not descended from TUnrelated' (-not $o3.is_descendant -and -not $o3.implements)

if (Test-Path $db) { Remove-Item $db -Force -ErrorAction SilentlyContinue }
if ($fail -gt 0) { Write-Host "$fail FAILED"; exit 1 }
Write-Host 'ancestry: all pass'; exit 0
