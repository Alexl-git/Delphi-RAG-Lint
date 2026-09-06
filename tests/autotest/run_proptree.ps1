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
# 'Continue' not 'Stop': the native drag-lint exe prints a '(loaded defaults)' note
# to stderr, which under 'Stop' PowerShell turns into a terminating error mid-run.
# Pass/fail here is driven by explicit Check() calls + the final exit code.
$ErrorActionPreference = 'Continue'
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

  // --refs-as-leaves fixture: a referenced TComponent must be a LEAF (not expanded),
  // while an OWNED TPersistent sub-object still expands. TComp descends from
  // TComponent and carries a Caption property that would otherwise surface as
  // Ref.Caption; TRefHost has an owned TInner (expands to Owned.Shade) plus a
  // referenced TComp (Ref -- a leaf under --refs-as-leaves).
  TComp = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

  TRefHost = class(TComponent)
  private
    FOwned: TInner;
    FRef: TComp;
  published
    property Owned: TInner read FOwned write FOwned;
    property Ref: TComp read FRef write FRef;
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

# --- --refs-as-leaves: a referenced TComponent property is a LEAF (not expanded);
#     an owned TPersistent sub-object still expands. Default (no flag) expands both.
Write-Host ''
Write-Host 'proptree PropFix.TRefHost (default = expand refs)' -ForegroundColor Cyan
Push-Location $WorkDir
try { $defRaw = (& $Exe proptree --qname 'PropFix.TRefHost' --format json --db $db) -join "`n" } finally { Pop-Location }
Write-Host 'proptree PropFix.TRefHost --refs-as-leaves (= reference leaves)' -ForegroundColor Cyan
Push-Location $WorkDir
try { $refRaw = (& $Exe proptree --qname 'PropFix.TRefHost' --refs-as-leaves --format json --db $db) -join "`n" } finally { Pop-Location }
$defTree = $null; try { $defTree = $defRaw | ConvertFrom-Json } catch { }
$refTree = $null; try { $refTree = $refRaw | ConvertFrom-Json } catch { }
if (($null -ne $defTree) -and ($null -ne $refTree)) {
  $defPaths = @(@($defTree.properties) | ForEach-Object { $_.path })
  $refPaths = @(@($refTree.properties) | ForEach-Object { $_.path })
  Check "default: referenced TComp EXPANDS (Ref.Caption present)" `
        ($defPaths -contains 'Ref.Caption') ("paths=" + ($defPaths -join ', '))
  Check "--refs-as-leaves: Ref present as a leaf" `
        ($refPaths -contains 'Ref') ("paths=" + ($refPaths -join ', '))
  Check "--refs-as-leaves: NO Ref.* children (reference not expanded)" `
        (-not @($refPaths | Where-Object { $_ -like 'Ref.*' })) ("paths=" + ($refPaths -join ', '))
  Check "--refs-as-leaves: owned TPersistent still expands (Owned.Shade present)" `
        ($refPaths -contains 'Owned.Shade') ("paths=" + ($refPaths -join ', '))
  $refNode = @($refTree.properties) | Where-Object { $_.path -eq 'Ref' } | Select-Object -First 1
  if ($null -ne $refNode) {
    Check "--refs-as-leaves: Ref node is_class_typed == false (a reference)" `
          ($refNode.is_class_typed -eq $false) "is_class_typed=$($refNode.is_class_typed)"
  }
} else {
  Check 'proptree TRefHost (both modes) parse as JSON' $false "def=$defRaw`nref=$refRaw"
}

# ---------------------------------------------------------------------------
# The `default` clause (proptree/2, additive keys has_default + default_value).
#
# WHY IT IS IN THE TREE AT ALL: a .dfm is SPARSE -- Delphi streams a published
# property only when its value DIFFERS from the `default` declared on it. So a
# property missing from a .dfm block is not missing information, it is an UNREAD
# value, and DRagLint.Convert.DfmReemit (which is PURE and cannot look anything
# up) reads it from here.
#
# Four cases, and the distinction between the last two is the whole point:
#   default <X>          -> has_default, value X
#   nodefault            -> NO default, and it STOPS the ancestor walk
#   bare redeclaration   -> keeps the ANCESTOR's default (walk up)
#   no clause anywhere   -> no default (always streamed; absence is UNKNOWN)
# ---------------------------------------------------------------------------
$DefBody = @'
unit DefFix;

interface

type
  TMode = (omA, omB);

  TDefBase = class
  private
    FFlag: Boolean;
    FMode: TMode;
    FCap : string;
    FNone: Integer;
  published
    property Flag: Boolean read FFlag write FFlag default True;
    property Mode: TMode read FMode write FMode default omA;
    property Cap: string read FCap write FCap;
    property None: Integer read FNone write FNone;
  end;

  TDefChild = class(TDefBase)
  published
    property Flag;                 // bare redeclaration -- keeps TDefBase's default True
    property Mode nodefault;       // explicitly cancels the inherited default
  end;

  TOpt  = (oA, oB, oC);
  TOpts = set of TOpt;

  { Two shapes the first cut of this feature got wrong, both pervasive in the
    real VCL. Their values are only ever CONSUMED by convert-reemit, so a
    tokeniser bug here surfaces as a malformed .dfm rather than a wrong query. }
  TDefEdge = class
  private
    FAnchors: TOpts;
    FColor  : Integer;
    FKeep   : Boolean;
    FPlain  : Integer;
  published
    { A SET default contains a space, so stopping the token at the first space
      truncated it to `[oA,` -- a malformed value once it is emitted. }
    property Anchors: TOpts read FAnchors write FAnchors default [oA, oB];
    { A conditional `stored` DESTROYS the sparse-DFM premise: with ParentColor
      set, Vcl.Controls' Color is omitted regardless of its value, so absence
      does NOT mean "at the default". There is no usable default here. }
    property Color: Integer read FColor write FColor stored IsColorStored default 7;
    { `stored True` is the explicit form of the normal case and stays usable. }
    property Keep: Boolean read FKeep write FKeep stored True default True;
    { control: an ordinary default alongside the two above. }
    property Plain: Integer read FPlain write FPlain default 3;
  end;

implementation

end.
'@
Write-Ascii (Join-Path $work 'DefFix.pas') $DefBody
$idx2 = & $Exe index $work --db $db 2>&1
Check 'default-clause: reindex exits 0' ($LASTEXITCODE -eq 0) "$($idx2 -join ' | ')"

$defJson = (& $Exe proptree --qname 'DefFix.TDefChild' --format json --db $db 2>$null) -join "`n"
$defDoc = $null
try { $defDoc = $defJson | ConvertFrom-Json } catch { $defDoc = $null }
Check 'default-clause: proptree parses' ($null -ne $defDoc) "raw=$defJson"
if ($null -ne $defDoc) {
  function Prop($n) { @($defDoc.properties) | Where-Object { $_.path -eq $n } | Select-Object -First 1 }

  # Inherited, carries a real default.
  $pCap = Prop 'Cap'; $pNone = Prop 'None'; $pFlag = Prop 'Flag'; $pMode = Prop 'Mode'

  Check 'default-clause: bare redeclaration INHERITS the ancestor default (Flag=True)' `
    ($null -ne $pFlag -and $pFlag.has_default -eq $true -and $pFlag.default_value -eq 'True') `
    "has=$($pFlag.has_default) val=$($pFlag.default_value)"

  # nodefault must STOP the walk -- not fall through to TDefBase's 'default omA'.
  Check 'default-clause: nodefault cancels the inherited default (Mode)' `
    ($null -ne $pMode -and $pMode.has_default -eq $false -and $pMode.default_value -eq '') `
    "has=$($pMode.has_default) val=$($pMode.default_value)"

  # A string property cannot carry `default`; absence here is genuinely unknown.
  Check 'default-clause: a property with no clause has no default (Cap)' `
    ($null -ne $pCap -and $pCap.has_default -eq $false) "has=$($pCap.has_default)"
  Check 'default-clause: an ordinal with no clause has no default (None)' `
    ($null -ne $pNone -and $pNone.has_default -eq $false) "has=$($pNone.has_default)"

  # POSITIVE CONTROL: without this, every assertion above is satisfied by the
  # resolver returning False for everything.
  $anyDefault = @(@($defDoc.properties) | Where-Object { $_.has_default -eq $true }).Count
  Check 'default-clause: POSITIVE CONTROL -- at least one property DOES resolve a default' `
    ($anyDefault -ge 1) "count=$anyDefault"
}

# The base class read directly: its own declarations, no walking involved.
$baseJson = (& $Exe proptree --qname 'DefFix.TDefBase' --format json --db $db 2>$null) -join "`n"
$baseDoc = $null
try { $baseDoc = $baseJson | ConvertFrom-Json } catch { $baseDoc = $null }
if ($null -ne $baseDoc) {
  $bMode = @($baseDoc.properties) | Where-Object { $_.path -eq 'Mode' } | Select-Object -First 1
  Check 'default-clause: enum default is captured verbatim (Mode=omA)' `
    ($bMode.has_default -eq $true -and $bMode.default_value -eq 'omA') `
    "has=$($bMode.has_default) val=$($bMode.default_value)"
} else {
  Check 'default-clause: base proptree parses' $false "raw=$baseJson"
}

# --- Set defaults, and `stored` as a veto on the sparse-DFM premise ----------
# These two shapes are pervasive in the VCL and both were wrong in the first
# cut. They matter because convert-reemit EMITS default_value into a .dfm: a
# truncated set is a malformed form file, and a conditionally-stored property
# read as "at its default" writes a value the form never had.
$edgeJson = (& $Exe proptree --qname 'DefFix.TDefEdge' --format json --db $db 2>$null) -join "`n"
$edgeDoc = $null
try { $edgeDoc = $edgeJson | ConvertFrom-Json } catch { $edgeDoc = $null }
if ($null -ne $edgeDoc) {
  $eAnchors = @($edgeDoc.properties) | Where-Object { $_.path -eq 'Anchors' } | Select-Object -First 1
  $eColor   = @($edgeDoc.properties) | Where-Object { $_.path -eq 'Color'   } | Select-Object -First 1
  $eKeep    = @($edgeDoc.properties) | Where-Object { $_.path -eq 'Keep'    } | Select-Object -First 1
  $ePlain   = @($edgeDoc.properties) | Where-Object { $_.path -eq 'Plain'   } | Select-Object -First 1

  # A set default must survive WHOLE. `-eq` not `-match`: the bug produced the
  # PREFIX '[oA,', which any substring assertion would happily accept.
  Check 'default-clause: a SET default is captured whole, not truncated at the space' `
    ($null -ne $eAnchors -and $eAnchors.has_default -eq $true -and `
     $eAnchors.default_value -eq '[oA, oB]') `
    "has=$($eAnchors.has_default) val='$($eAnchors.default_value)'"

  # A conditional `stored` means absence carries NO information, so there is no
  # usable default even though a `default` clause is present two tokens away.
  Check 'default-clause: `stored <fn>` vetoes the default entirely (Color)' `
    ($null -ne $eColor -and $eColor.has_default -eq $false -and $eColor.default_value -eq '') `
    "has=$($eColor.has_default) val='$($eColor.default_value)'"

  # CONTROLS. Without these, the veto above is equally satisfied by "any
  # property mentioning `stored`, or indeed everything, resolves to nothing".
  Check 'default-clause: CONTROL -- `stored True` keeps its default (Keep)' `
    ($null -ne $eKeep -and $eKeep.has_default -eq $true -and $eKeep.default_value -eq 'True') `
    "has=$($eKeep.has_default) val='$($eKeep.default_value)'"
  Check 'default-clause: CONTROL -- a plain default beside them is unaffected (Plain=3)' `
    ($null -ne $ePlain -and $ePlain.has_default -eq $true -and $ePlain.default_value -eq '3') `
    "has=$($ePlain.has_default) val='$($ePlain.default_value)'"
} else {
  Check 'default-clause: edge-case proptree parses' $false "raw=$edgeJson"
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
