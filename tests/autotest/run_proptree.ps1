<#
  run_proptree.ps1 -- proptree verb headless test (Track 3 Batch 1, Task 1).

  The proptree verb is an index-driven RECURSIVE deep-property enumerator: it
  walks a class's kind='property' child symbols, parses each type from the
  property Signature, and RECURSES into class-typed property types (depth-capped
  + visited-TYPE-set cycle guard), producing flattened dotted paths such as
  'Font.Color' or 'Inner.Shade'.

  FIXTURE (built fresh in a temp workdir, then indexed as a whole tree):
    PropFix.pas -- unit PropFix; TInner(TPersistent) has a scalar property Shade
                    (Integer). TOuter(TPersistent) has a CLASS-typed property
                    Inner (TInner) and a scalar property Name (string). Walking
                    TOuter must recurse THROUGH Inner into TInner.Shade, yielding
                    the deep dotted path 'Inner.Shade'.

  Load-bearing assertions (proptree --qname PropFix.TOuter --format json):
    - schema is proptree/1
    - root_type matches 'TOuter'
    - property paths contain 'Name'  (scalar, top-level)
    - property paths contain 'Inner' (class-typed, top-level)
    - property paths contain 'Inner.Shade' (THE DEEP RECURSED MATCH)
    - the 'Inner.Shade' node's type matches 'Integer'
    - the 'Inner' node is class-typed (is_class_typed == True)

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-proptree by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-proptree"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory $work | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$PropBody = @'
unit PropFix;

interface

type
  TInner = class(TPersistent)
  private
    FShade: Integer;
  published
    property Shade: Integer read FShade write FShade;
  end;

  TOuter = class(TPersistent)
  private
    FInner: TInner;
    FName: string;
  published
    property Inner: TInner read FInner write FInner;
    property Name: string read FName write FName;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'PropFix.pas') $PropBody

$db = Join-Path $WorkDir 'propfix.sqlite'

Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
$indexExit = $LASTEXITCODE
Check 'index exits 0' ($indexExit -eq 0) "exit=$indexExit; $($indexOut -join ' | ')"

Write-Host ''
Write-Host 'proptree --qname PropFix.TOuter --format json' -ForegroundColor Cyan
Push-Location $WorkDir
try {
  $jsonRaw = (& $Exe proptree --qname 'PropFix.TOuter' --format json --db $db) -join "`n"
  $ptExit = $LASTEXITCODE
} finally {
  Pop-Location
}
Check 'proptree exits 0' ($ptExit -eq 0) "exit=$ptExit"

$tree = $null
try {
  $tree = $jsonRaw | ConvertFrom-Json
} catch {
  Check 'proptree --format json parses as JSON' $false "parse error: $($_.Exception.Message); raw=$jsonRaw"
}

if ($null -ne $tree) {
  Check 'proptree --format json parses as JSON' $true

  Check 'schema is proptree/1' ($tree.schema -eq 'proptree/1') "schema=$($tree.schema)"
  Check 'root_type matches TOuter' ($tree.root_type -match 'TOuter') "root_type=$($tree.root_type)"

  $props = @($tree.properties)
  $paths = @($props | ForEach-Object { $_.path })
  Check 'has >=1 property' ($props.Count -ge 1) ("paths=" + ($paths -join ', '))

  Check "property paths contain 'Name' (scalar)"  ($paths -contains 'Name')  ("paths=" + ($paths -join ', '))
  Check "property paths contain 'Inner' (class)"  ($paths -contains 'Inner') ("paths=" + ($paths -join ', '))
  Check "property paths contain 'Inner.Shade' (DEEP RECURSED)" ($paths -contains 'Inner.Shade') ("paths=" + ($paths -join ', '))

  $innerShade = $props | Where-Object { $_.path -eq 'Inner.Shade' } | Select-Object -First 1
  if ($null -ne $innerShade) {
    Check "'Inner.Shade' type matches Integer" ($innerShade.type -match 'Integer') "type=$($innerShade.type)"
  } else {
    Check "'Inner.Shade' node present" $false ''
  }

  $inner = $props | Where-Object { $_.path -eq 'Inner' } | Select-Object -First 1
  if ($null -ne $inner) {
    Check "'Inner' node is class-typed" ($inner.is_class_typed -eq $true) "is_class_typed=$($inner.is_class_typed)"
  } else {
    Check "'Inner' node present" $false ''
  }
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
