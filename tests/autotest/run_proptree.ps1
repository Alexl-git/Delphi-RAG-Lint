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

  // Forward declaration BEFORE the real body -- the DevExpress pattern. The
  // parser emits TWO skClass symbols for TFwd (the stub 'class;' and the body).
  // proptree must resolve TFwd to the BODY (which has the property), not the
  // childless forward stub.
  TFwd = class;

  TFwdHolder = class(TPersistent)
  end;

  TFwd = class(TPersistent)
  private
    FTag: Integer;
  published
    property Tag: Integer read FTag write FTag;
  end;

  // A class that INHERITS from the forward-declared TFwd and REDECLARES its
  // inherited property with an empty signature ('property Tag;'). Resolving
  // TFwdChild.Tag's type requires the ancestry edge TFwdChild->TFwd to be
  // RESOLVED at index time. The forward-decl stub made TFwd an ambiguous
  // same-file candidate, so ResolveAncestry left the edge unresolved and the
  // inherited type came back 'unknown'. This is the regression guard.
  TFwdChild = class(TFwd)
  published
    property Tag;
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

  # proptree/2 (Task 2, R2): schema bumped proptree/1 -> proptree/2 (additive;
  # this file's own assertions below are unaffected -- same paths/types/
  # structure -- confirming the bump is back-compat for everything but the
  # literal schema string).
  Check 'schema is proptree/2' ($tree.schema -eq 'proptree/2') "schema=$($tree.schema)"
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

# --- Forward-declaration resolution: proptree on a class with a 'class;' forward
#     decl before its body must resolve to the BODY (with the property), not the
#     childless forward stub. Regression guard for the DevExpress-cx case where
#     every class is forward-declared and proptree returned 0 properties.
Write-Host ''
Write-Host 'proptree --qname PropFix.TFwd --format json (forward-decl case)' -ForegroundColor Cyan
Push-Location $WorkDir
try {
  $fwdRaw = (& $Exe proptree --qname 'PropFix.TFwd' --format json --db $db) -join "`n"
  $fwdExit = $LASTEXITCODE
} finally {
  Pop-Location
}
Check 'proptree TFwd exits 0' ($fwdExit -eq 0) "exit=$fwdExit"

$fwdTree = $null
try { $fwdTree = $fwdRaw | ConvertFrom-Json } catch { }
if ($null -ne $fwdTree) {
  $fwdPaths = @(@($fwdTree.properties) | ForEach-Object { $_.path })
  Check "TFwd resolves to the BODY (has property 'Tag'), not the forward stub" `
        ($fwdPaths -contains 'Tag') ("paths=" + ($fwdPaths -join ', '))
  $tag = @($fwdTree.properties) | Where-Object { $_.path -eq 'Tag' } | Select-Object -First 1
  if ($null -ne $tag) {
    Check "'Tag' type matches Integer" ($tag.type -match 'Integer') "type=$($tag.type)"
  } else {
    Check "'Tag' node present" $false ''
  }
} else {
  Check 'proptree TFwd --format json parses as JSON' $false "raw=$fwdRaw"
}

# --- Inherited-from-forward-declared: TFwdChild(TFwd) redeclares Tag with an
#     empty signature. Its type resolves ONLY if the ancestry edge
#     TFwdChild->TFwd was resolved at index time (ResolveAncestry must not treat
#     the TFwd forward-decl stub as an ambiguous second candidate).
Write-Host ''
Write-Host 'proptree --qname PropFix.TFwdChild --format json (inherited-from-forward-decl)' -ForegroundColor Cyan
Push-Location $WorkDir
try {
  $fcRaw = (& $Exe proptree --qname 'PropFix.TFwdChild' --format json --db $db) -join "`n"
} finally {
  Pop-Location
}
$fcTree = $null
try { $fcTree = $fcRaw | ConvertFrom-Json } catch { }
if ($null -ne $fcTree) {
  $fcTag = @($fcTree.properties) | Where-Object { $_.path -eq 'Tag' } | Select-Object -First 1
  if ($null -ne $fcTag) {
    Check "TFwdChild.Tag inherited type resolves to Integer (ancestry edge resolved)" `
          ($fcTag.type -match 'Integer') "type=$($fcTag.type)"
  } else {
    Check "TFwdChild has property 'Tag'" $false ("paths=" + (@(@($fcTree.properties) | ForEach-Object { $_.path }) -join ', '))
  }
} else {
  Check 'proptree TFwdChild --format json parses as JSON' $false "raw=$fcRaw"
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
