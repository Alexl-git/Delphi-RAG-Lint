<#
  run_proptree_polymorphic.ps1 -- proptree R3 CLASS-ACCURATE concrete polymorphic
  type resolution (Track 3, proptree assignability engine, Task 3).

  R3: for a queried class, a redeclared property ('Props', the fixture's stand-in
  for the classic DevExpress 'Properties' case) must resolve to THAT class's
  most-derived CONCRETE (non-empty-signature) type and recurse into THAT --
  never a base type, and never another class's type. A most-derived
  visibility-only (bare 'property Props;', empty signature) redeclaration must
  NOT collapse the type to the base -- it must prefer the nearest CONCRETE
  own-class declaration in the class chain.

  FIXTURE (PolyFix.pas), two scenarios in one file:

  Scenario 1 -- the brief-prescribed sibling/covariance fixture:
    TBaseProps  (Common: Integer)               -- the base Props type
    TCheckProps = class(TBaseProps)  (+CheckOnly: Boolean) -- checkbox-only leaf
    TBtnProps   = class(TBaseProps)  (+BtnOnly: Boolean)   -- button-edit-only leaf
    TBaseEdit   -- property Props: TBaseProps
    TCheckBox   = class(TBaseEdit)   -- property Props: TCheckProps (own concrete redecl)
    TBtnEdit    = class(TBaseEdit)   -- property Props: TBtnProps   (own concrete redecl)
    TCheckBoxEx = class(TCheckBox)   -- property Props;  (BARE covariant redeclaration --
                                          must resolve to TCheckProps, the nearest
                                          concrete OWN-CLASS declaration, NOT collapse
                                          to TBaseEdit's TBaseProps)

  Scenario 2 -- REGRESSION GUARD found during this task's TDD reproduction pass:
  ResolveInheritedType and ResolveViaBridgedAncestry.Climb both walked the RAW
  (unfiltered) GetTransitiveAncestors closure, which also contains any INTERFACE
  ancestors a class implements (Delphi interfaces can declare properties too,
  e.g. 'property Props: T read GetProps;'). Without an (A.Kind = 'class') guard
  -- mirroring the one ClassChain already uses for CollectProps' shadowing --
  an implemented interface's own same-named property (a wholly UNRELATED type)
  could be found and returned BEFORE the walk reached the queried class's real
  base, i.e. a wrong-CLASS leaf leaking in from OUTSIDE the class hierarchy
  entirely. Confirmed RED pre-fix: TInterfaceDerived.Props resolved to
  'TWeirdProps' (from IPropsIntf) instead of 'TBaseProps'.
    TWeirdProps    (WeirdOnly: Boolean)          -- unrelated type, must NEVER appear
    IPropsIntf     -- interface; property Props: TWeirdProps read GetProps
    TPassThrough  = class(TBaseEdit)              -- pure pass-through, no own Props
                        redeclaration at all (the real declaration is one hop
                        further up, on TBaseEdit)
    TInterfaceDerived = class(TPassThrough, IPropsIntf) -- property Props;  (BARE)
                        must resolve to TBaseProps (the class chain), NEVER
                        TWeirdProps (the interface).

  Load-bearing assertions (proptree --qname PolyFix.<Class> --format json):
    - PolyFix.TCheckBox:        Props.type == 'TCheckProps'; has 'Props.CheckOnly';
                                 does NOT have 'Props.BtnOnly'
    - PolyFix.TBtnEdit:         Props.type == 'TBtnProps';   has 'Props.BtnOnly'
    - PolyFix.TCheckBoxEx:      Props.type == 'TCheckProps' (NOT 'TBaseProps');
                                 has 'Props.CheckOnly'
    - PolyFix.TInterfaceDerived: Props.type == 'TBaseProps' (NOT 'TWeirdProps');
                                 has 'Props.Common'; does NOT have 'Props.WeirdOnly'

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-proptree-polymorphic by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-proptree-polymorphic"
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

Write-Ascii (Join-Path $work 'PolyFix.pas') @'
unit PolyFix;

interface

type
  // --- Scenario 1: sibling concrete redeclarations + a bare covariant
  // redeclaration. -----------------------------------------------------
  TBaseProps = class(TPersistent)
  private
    FCommon: Integer;
  published
    property Common: Integer read FCommon write FCommon;
  end;

  TCheckProps = class(TBaseProps)
  private
    FCheckOnly: Boolean;
  published
    property CheckOnly: Boolean read FCheckOnly write FCheckOnly;
  end;

  TBtnProps = class(TBaseProps)
  private
    FBtnOnly: Boolean;
  published
    property BtnOnly: Boolean read FBtnOnly write FBtnOnly;
  end;

  TBaseEdit = class(TPersistent)
  private
    FBaseEditProps: TBaseProps;
  published
    property Props: TBaseProps read FBaseEditProps write FBaseEditProps;
  end;

  TCheckBox = class(TBaseEdit)
  private
    FCheckBoxProps: TCheckProps;
  published
    property Props: TCheckProps read FCheckBoxProps write FCheckBoxProps;
  end;

  TBtnEdit = class(TBaseEdit)
  private
    FBtnEditProps: TBtnProps;
  published
    property Props: TBtnProps read FBtnEditProps write FBtnEditProps;
  end;

  TCheckBoxEx = class(TCheckBox)
  published
    property Props;   // bare covariant redeclaration -- must resolve to TCheckProps
  end;

  // --- Scenario 2: interface-interposition regression guard. -----------
  TWeirdProps = class(TPersistent)
  private
    FWeirdOnly: Boolean;
  published
    property WeirdOnly: Boolean read FWeirdOnly write FWeirdOnly;
  end;

  IPropsIntf = interface
    ['{12345678-1234-1234-1234-123456789ABC}']
    function GetProps: TWeirdProps;
    property Props: TWeirdProps read GetProps;
  end;

  TPassThrough = class(TBaseEdit)
    // Deliberately does NOT redeclare Props -- a pure pass-through link, so the
    // nearest OWN-CLASS declaration is one hop further up, on TBaseEdit.
  end;

  TInterfaceDerived = class(TPassThrough, IPropsIntf)
  private
    function GetProps: TWeirdProps;
  published
    property Props;   // bare -- must resolve to TBaseProps, NEVER TWeirdProps
  end;

implementation

end.
'@

$db = Join-Path $WorkDir 'polyfix.sqlite'
Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
$indexExit = $LASTEXITCODE
Check 'index exits 0' ($indexExit -eq 0) "exit=$indexExit; $($indexOut -join ' | ')"

function Get-Tree([string]$Database, [string]$QName) {
  Push-Location $WorkDir
  try {
    $raw = (& $Exe proptree --qname $QName --format json --db $Database --no-write-back) -join "`n"
    $exit = $LASTEXITCODE
  } finally { Pop-Location }
  $tree = $null
  try { $tree = $raw | ConvertFrom-Json } catch { }
  return @{ Tree = $tree; Exit = $exit; Raw = $raw }
}

function ByPath($tree) {
  $map = @{}
  foreach ($p in @($tree.properties)) { $map[$p.path] = $p }
  return $map
}

# --- 1. PolyFix.TCheckBox -> Props.type == TCheckProps; CheckOnly present; ---
#        BtnOnly absent. ------------------------------------------------------
Write-Host ''
Write-Host 'proptree PolyFix.TCheckBox' -ForegroundColor Cyan
$r1 = Get-Tree $db 'PolyFix.TCheckBox'
Check 'TCheckBox: exits 0' ($r1.Exit -eq 0) "exit=$($r1.Exit)"
Check 'TCheckBox: --format json parses' ($null -ne $r1.Tree) "raw=$($r1.Raw)"
if ($null -ne $r1.Tree) {
  $bp1 = ByPath $r1.Tree
  if ($bp1.ContainsKey('Props')) {
    Check "TCheckBox: Props.type == 'TCheckProps'" ($bp1['Props'].type -eq 'TCheckProps') "type=$($bp1['Props'].type)"
  } else { Check 'TCheckBox: Props node present' $false '' }
  Check "TCheckBox: has 'Props.CheckOnly'" ($bp1.ContainsKey('Props.CheckOnly'))
  Check "TCheckBox: excludes 'Props.BtnOnly' (wrong-sibling leaf must NEVER appear)" (-not $bp1.ContainsKey('Props.BtnOnly'))
}

# --- 2. PolyFix.TBtnEdit -> Props.type == TBtnProps. --------------------------
Write-Host ''
Write-Host 'proptree PolyFix.TBtnEdit' -ForegroundColor Cyan
$r2 = Get-Tree $db 'PolyFix.TBtnEdit'
Check 'TBtnEdit: exits 0' ($r2.Exit -eq 0) "exit=$($r2.Exit)"
if ($null -ne $r2.Tree) {
  $bp2 = ByPath $r2.Tree
  if ($bp2.ContainsKey('Props')) {
    Check "TBtnEdit: Props.type == 'TBtnProps'" ($bp2['Props'].type -eq 'TBtnProps') "type=$($bp2['Props'].type)"
  } else { Check 'TBtnEdit: Props node present' $false '' }
  Check "TBtnEdit: has 'Props.BtnOnly'" ($bp2.ContainsKey('Props.BtnOnly'))
  Check "TBtnEdit: excludes 'Props.CheckOnly'" (-not $bp2.ContainsKey('Props.CheckOnly'))
} else {
  Check 'TBtnEdit: --format json parses' $false "raw=$($r2.Raw)"
}

# --- 3. PolyFix.TCheckBoxEx (bare covariant redecl) -> Props.type ==       ---
#        TCheckProps, NOT collapsed to TBaseProps. -----------------------------
Write-Host ''
Write-Host 'proptree PolyFix.TCheckBoxEx (bare covariant redeclaration)' -ForegroundColor Cyan
$r3 = Get-Tree $db 'PolyFix.TCheckBoxEx'
Check 'TCheckBoxEx: exits 0' ($r3.Exit -eq 0) "exit=$($r3.Exit)"
if ($null -ne $r3.Tree) {
  $bp3 = ByPath $r3.Tree
  if ($bp3.ContainsKey('Props')) {
    Check "TCheckBoxEx: Props.type == 'TCheckProps' (NOT collapsed to base)" ($bp3['Props'].type -eq 'TCheckProps') "type=$($bp3['Props'].type)"
  } else { Check 'TCheckBoxEx: Props node present' $false '' }
  Check "TCheckBoxEx: has 'Props.CheckOnly'" ($bp3.ContainsKey('Props.CheckOnly'))
} else {
  Check 'TCheckBoxEx: --format json parses' $false "raw=$($r3.Raw)"
}

# --- 4. PolyFix.TInterfaceDerived (bare redecl behind a pass-through link,  ---
#        class ALSO implements an interface declaring the same property     ---
#        name with an unrelated type) -> Props.type == TBaseProps, NEVER    ---
#        TWeirdProps (the interface's type). REGRESSION GUARD.              ---
Write-Host ''
Write-Host 'proptree PolyFix.TInterfaceDerived (interface-interposition regression guard)' -ForegroundColor Cyan
$r4 = Get-Tree $db 'PolyFix.TInterfaceDerived'
Check 'TInterfaceDerived: exits 0' ($r4.Exit -eq 0) "exit=$($r4.Exit)"
if ($null -ne $r4.Tree) {
  $bp4 = ByPath $r4.Tree
  if ($bp4.ContainsKey('Props')) {
    Check "TInterfaceDerived: Props.type == 'TBaseProps' (NOT the interface's 'TWeirdProps')" ($bp4['Props'].type -eq 'TBaseProps') "type=$($bp4['Props'].type)"
  } else { Check 'TInterfaceDerived: Props node present' $false '' }
  Check "TInterfaceDerived: has 'Props.Common'" ($bp4.ContainsKey('Props.Common'))
  Check "TInterfaceDerived: excludes 'Props.WeirdOnly' (wrong-class leaf from the interface must NEVER appear)" (-not $bp4.ContainsKey('Props.WeirdOnly'))
} else {
  Check 'TInterfaceDerived: --format json parses' $false "raw=$($r4.Raw)"
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
