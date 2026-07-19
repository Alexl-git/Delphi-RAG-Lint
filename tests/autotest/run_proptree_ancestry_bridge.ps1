<#
  run_proptree_ancestry_bridge.ps1 -- proptree LAZY ancestry-bridge + write-back.

  THE BUG (confirmed against the real DevExpress library index): when a published
  property is a BARE inherited redeclaration ('property Align;') on a class whose
  ancestry chain is broken by a TYPE ALIAS ancestor (e.g.
  'cxButtons.TcxBaseButton = Vcl.StdCtrls.TCustomButton'), ResolveAncestry leaves
  the edge UNRESOLVED (its candidate set is class/interface only, so a type-alias
  ancestor never resolves). proptree then cannot type the property and emits
  'unknown' for every VCL-inherited property (Align, Caption, Anchors, ...).

  THE FIX: when proptree is about to return 'unknown', it walks UP the ancestry
  BRIDGING each unresolved ancestor NAME to its defining class by a scope-aware,
  alias-following lookup, finds the ancestor that really declares the property
  with a known type, and (with --write-back) memoizes the resolved type onto the
  property row so the next read is a plain hit.

  FIXTURE (three units, indexed as one tree):
    VclKit.pas  -- TAlign enum; a resolved VCL-style chain
                   TControl(TPersistent) [property Align: TAlign]
                     <- TWinControl <- TButtonControl <- TCustomButton
    FmxKit.pas  -- TAlignLayout enum; a DECOY 'TCustomButton' with
                   'property Align: TAlignLayout'. Same simple name as VclKit's
                   TCustomButton => the ancestor name 'TCustomButton' is AMBIGUOUS.
    CxKit.pas   -- uses VclKit (NOT FmxKit).
                   'type TcxBaseButton = TCustomButton;'   (the alias => broken edge)
                   TcxCustomButton(TcxBaseButton)
                   TcxButton(TcxCustomButton) published 'property Align;' (bare)

  Load-bearing assertions (proptree --qname CxKit.TcxButton --format json):
    - Align resolves to 'TAlign'  (was 'unknown' before the fix)     <-- THE FIX
    - Align is NOT 'TAlignLayout' (the FMX decoy) -- scope disambiguation works
    - write-back: after 'proptree --write-back' the TcxButton.Align property row's
      stored signature becomes ': TAlign' (memoized)
    - idempotency: a SECOND --write-back leaves the signature exactly ': TAlign'
      (not doubled), i.e. the second run is a plain hit / no further mutation.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-proptree-bridge"
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

Write-Ascii (Join-Path $work 'VclKit.pas') @'
unit VclKit;

interface

type
  TAlign = (alNone, alTop, alBottom, alClient);

  TControl = class(TPersistent)
  private
    FAlign: TAlign;
  published
    property Align: TAlign read FAlign write FAlign;
  end;

  TWinControl = class(TControl)
  end;

  TButtonControl = class(TWinControl)
  end;

  TCustomButton = class(TButtonControl)
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'FmxKit.pas') @'
unit FmxKit;

interface

type
  TAlignLayout = (Center, Client, Top);

  // DECOY: same simple name 'TCustomButton' as VclKit's, but Align is a DIFFERENT
  // type. If the bridge picks THIS by bare name it would wrongly type Align as
  // TAlignLayout; scope must prefer VclKit (which CxKit actually uses).
  TCustomButton = class(TPersistent)
  private
    FAlign: TAlignLayout;
  published
    property Align: TAlignLayout read FAlign write FAlign;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'CxKit.pas') @'
unit CxKit;

interface

uses
  VclKit;

type
  // A TYPE ALIAS ancestor. ResolveAncestry's candidate set is class/interface
  // only, so the edge TcxCustomButton -> TcxBaseButton is left UNRESOLVED --
  // exactly the DevExpress 'TcxBaseButton = TCustomButton' break.
  TcxBaseButton = TCustomButton;

  TcxCustomButton = class(TcxBaseButton)
  end;

  TcxButton = class(TcxCustomButton)
  published
    property Align;
    property Caption;
  end;

implementation

end.
'@

$db = Join-Path $WorkDir 'bridge.sqlite'
Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($indexOut -join ' | ')"

function Get-Tree([string]$Database, [string]$QName, [switch]$WriteBack) {
  Push-Location $WorkDir
  try {
    if ($WriteBack) {
      $raw = (& $Exe proptree --qname $QName --format json --write-back --db $Database) -join "`n"
    } else {
      $raw = (& $Exe proptree --qname $QName --format json --db $Database) -join "`n"
    }
  } finally { Pop-Location }
  return ($raw | ConvertFrom-Json)
}

$script:PyQuery = Join-Path $WorkDir 'read_align_sig.py'
Write-Ascii $script:PyQuery @'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1]); c = con.cursor()
r = c.execute(
    "SELECT signature FROM symbols WHERE name='Align' AND kind='property' "
    "AND parent_id IN (SELECT id FROM symbols WHERE name='TcxButton' AND kind='class')"
).fetchone()
print('' if r is None else r[0])
con.close()
'@

function Get-AlignSig([string]$Database) {
  # Raw stored signature of CxKit.TcxButton.Align (proof of memoization).
  return (python $script:PyQuery $Database).Trim()
}

# --- 1. Read-only resolution: Align must resolve to TAlign (was 'unknown'). ------
Write-Host ''
Write-Host 'proptree CxKit.TcxButton (read-only)' -ForegroundColor Cyan
$tree = Get-Tree $db 'CxKit.TcxButton'
$align = @($tree.properties) | Where-Object { $_.path -eq 'Align' } | Select-Object -First 1
if ($null -ne $align) {
  Check "Align type resolves to 'TAlign' (bridged across the alias break)" ($align.type -eq 'TAlign') "type=$($align.type)"
  Check "Align is NOT the FMX decoy 'TAlignLayout' (scope disambiguation)"  ($align.type -ne 'TAlignLayout') "type=$($align.type)"
  Check "Align is NOT 'unknown'" ($align.type -ne 'unknown') "type=$($align.type)"
} else {
  Check "CxKit.TcxButton has property 'Align'" $false ("paths=" + (@(@($tree.properties)|ForEach-Object{$_.path}) -join ', '))
}

# --- 2. Write-back memoization + idempotency. ------------------------------------
$dbw = Join-Path $WorkDir 'bridge_wb.sqlite'
Copy-Item $db $dbw -Force
$sig0 = Get-AlignSig $dbw
Check "before write-back: TcxButton.Align signature is empty" ($sig0 -eq '') "sig='$sig0'"

Write-Host ''
Write-Host 'proptree CxKit.TcxButton --write-back (1st)' -ForegroundColor Cyan
$null = Get-Tree $dbw 'CxKit.TcxButton' -WriteBack
$sig1 = Get-AlignSig $dbw
Check "after 1st write-back: Align signature memoized to ': TAlign'" ($sig1 -eq ': TAlign') "sig='$sig1'"

Write-Host ''
Write-Host 'proptree CxKit.TcxButton --write-back (2nd, idempotent)' -ForegroundColor Cyan
$null = Get-Tree $dbw 'CxKit.TcxButton' -WriteBack
$sig2 = Get-AlignSig $dbw
Check "after 2nd write-back: signature unchanged (idempotent, not doubled)" ($sig2 -eq ': TAlign') "sig='$sig2'"

# The memoized DB must still report TAlign on a plain read-only query (now a hit).
$treeAfter = Get-Tree $dbw 'CxKit.TcxButton'
$alignAfter = @($treeAfter.properties) | Where-Object { $_.path -eq 'Align' } | Select-Object -First 1
Check "memoized DB read-only still reports Align=TAlign" ($null -ne $alignAfter -and $alignAfter.type -eq 'TAlign') "type=$($alignAfter.type)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
