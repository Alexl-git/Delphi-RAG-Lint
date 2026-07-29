<#
  run_proptree_prop_type_scope.ps1 -- SCOPE-AWARE PROPERTY TYPES (Task 3b).

  WHAT THIS COVERS THAT NOTHING ELSE DOES

  run_proptree_scope_rule.ps1 proves the shared scope rule itself, and
  run_proptree_ancestor_climb.ps1 proves the ancestor CHAIN is bridged per hop
  with a cross-namespace refusal. Both stop at the chain. Neither says anything
  about the layer BELOW it: once proptree knows a property exists and knows its
  declared type TOKEN, which CLASS does that token name?

  Until Task 3b that question was answered by
  AStore.FindSymbolByExactNameAnywhere(Tok) -- no scope at all, first same-named
  symbol the index yields wins. Measured on library-Win64.sqlite:
  Vcl.Controls.TControl.Parent (declared ': TWinControl') resolved to
  FMX.Controls.Win.TWinControl and was recursed into, so 100% of that property's
  310 immediate children were declared in FMX.* classes -- an FMX property
  surface hanging off a VCL class. Four of the five worst offenders on
  Abcbtn.TabcToggleBtn behaved this way.

  Walk now resolves the token through ISymbolStore.ResolveTypeNameToClass, in
  the unit scope of the class that DECLARES that property, with the same
  CrossesGuiFramework (Vcl-vs-FMX) refusal the climb uses.

  CASES

    1 -- BOTH DIRECTIONS, ambiguous token. Two classes named 'TAmb3b', one in a
         Vcl.* unit and one in an FMX.* unit, each declaring a DIFFERENTLY-NAMED
         marker property. Two hosts, one per framework, each with
         'property Thing: TAmb3b'. Scope-unaware resolution returns the SAME
         class for both hosts, so whichever homonym the index happens to yield
         first, one of the two directions is wrong -- asserting both makes this
         RED regardless of index order.

    2 -- CRITERION 7 ONE LAYER DOWN: the scope must be the DECLARING class's
         unit, not the queried root's. 'Thing' is declared on a Vcl.*/FMX.* MID
         class; the two roots that inherit it both live in a THIRD unit whose
         namespace ('Zed') matches neither candidate. Scope by the root
         (the defect) -> rule 3 finds no 'Zed' candidate, declines, and 'Thing'
         has NO children in either direction. Scope by the declaring class
         (correct) -> each direction reaches its own framework. Both roots share
         one unit, so no single blanket scope can satisfy both: only a genuinely
         per-property scope passes.

    3 -- CRITERION 5 WHERE THE TOKEN HAS A SINGLE CANDIDATE. PickCandidate
         short-circuits on a lone candidate ('if Length(Types) = 1 then
         Exit(Types[0])'), so the scope rule -- and rule 3 with it -- never runs.
         A Vcl.* class whose property type names the ONE class of that name,
         living in an FMX.* unit, would otherwise be recursed into with no scope
         check at all. Paired with a same-namespace CONTROL of identical shape
         that must still expand, so the guard cannot pass by refusing everything.

    4 -- THE BRIDGED-PROPERTY PATH (ResolveViaBridgedAncestry.Climb), which
         reaches that same short-circuit independently of Walk. A BARE
         redeclared property on a Vcl.* class whose type can only be recovered
         across an unresolved type-ALIAS ancestor edge that leads to a lone
         FMX-declared class: the type must stay 'unknown', not be taken from the
         FMX class. Also paired with a same-namespace control.

    5/6 -- THE OTHER DIRECTION, and the reason cases 1-4 are not sufficient on
         their own: a namespace crossing that is LEGITIMATE must still succeed.
         The guard is Vcl-vs-FMX only, never a general different-namespace veto.
         Cases 1-4 all pair a refusal with a SAME-namespace control, so a guard
         that refused far too much would still pass every one of them -- and an
         earlier revision of this task did exactly that, vetoing the entire RTL
         surface referenced from VCL ('Vcl.Controls.TControl.Action:
         TBasicAction' and its 137 descendants, 'TWinControl.AlignControlList:
         TList', 'PopupComponent: TComponent', every 'PResource'). Case 5 pins
         the property-type path (Vcl.* host, System.* property type) and case 6
         pins the CHAIN path (Vcl.* class inheriting a System.* ancestor across
         an alias edge) -- the latter a latent defect in the Task 3 climb.

  Cases 3 and 4 differ from run_proptree_ancestor_climb.ps1's Case E: that one
  asserts an FMX-only ancestor's property is ABSENT (the CHAIN refused). Here
  the property is present either way -- what is at stake is its TYPE, and which
  class's surface hangs beneath it.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-proptree-prop-type-scope"
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

# --- Case 1/2 candidates: one ambiguous type name, one class per framework. ---
# Each declares a DIFFERENTLY-NAMED marker property, so which class was picked
# is visible in the child PATHS, not merely in a type string.
Write-Ascii (Join-Path $work 'Vcl.Cand3b.pas') @'
unit Vcl.Cand3b;

interface

type
  TAmb3b = class(TObject)
  private
    FMarkVcl3b: Integer;
  published
    property MarkVcl3b: Integer read FMarkVcl3b write FMarkVcl3b;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'FMX.Cand3b.pas') @'
unit FMX.Cand3b;

interface

type
  // Same simple name as Vcl.Cand3b.TAmb3b -- the token 'TAmb3b' is therefore
  // ambiguous, and a scope-unaware lookup must pick one of the two for EVERY
  // referencing class regardless of which framework that class belongs to.
  TAmb3b = class(TObject)
  private
    FMarkFmx3b: Integer;
  published
    property MarkFmx3b: Integer read FMarkFmx3b write FMarkFmx3b;
  end;

implementation

end.
'@

# --- Case 1 hosts: the property is declared ON the queried class itself. ------
# Deliberately NO uses clause in either host, so only rule 3 (framework prefix)
# can decide -- the same shape as the measured real-library root cause.
Write-Ascii (Join-Path $work 'Vcl.Host3b.pas') @'
unit Vcl.Host3b;

interface

type
  TVclHost3b = class(TObject)
  private
    FThing: TAmb3b;
  published
    property Thing: TAmb3b read FThing write FThing;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'FMX.Host3b.pas') @'
unit FMX.Host3b;

interface

type
  TFmxHost3b = class(TObject)
  private
    FThing: TAmb3b;
  published
    property Thing: TAmb3b read FThing write FThing;
  end;

implementation

end.
'@

# --- Case 2 mids: the property is declared one hop UP, in a different unit. ---
# Their own names are globally unique, so the root -> mid edges RESOLVE at index
# time and the walk genuinely crosses a unit boundary.
Write-Ascii (Join-Path $work 'Vcl.Mid3b.pas') @'
unit Vcl.Mid3b;

interface

type
  TVclMid3b = class(TObject)
  private
    FThing: TAmb3b;
  published
    property Thing: TAmb3b read FThing write FThing;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'FMX.Mid3b.pas') @'
unit FMX.Mid3b;

interface

type
  TFmxMid3b = class(TObject)
  private
    FThing: TAmb3b;
  published
    property Thing: TAmb3b read FThing write FThing;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Zed.Root3b.pas') @'
unit Zed.Root3b;

interface

// Namespace prefix 'Zed' matches NEITHER TAmb3b candidate, and there is no uses
// clause -- so resolving 'Thing's type in THIS unit's scope declines outright.
// Both roots live here on purpose: one blanket scope cannot serve both.

type
  TZedRoot3b  = class(TVclMid3b)
  end;

  TZedRootF3b = class(TFmxMid3b)
  end;

implementation

end.
'@

# --- Case 3: the token has exactly ONE definition, in the OTHER framework. ----
Write-Ascii (Join-Path $work 'FMX.Sole3b.pas') @'
unit FMX.Sole3b;

interface

type
  // Globally UNIQUE name -- PickCandidate short-circuits on a lone candidate,
  // so the shared scope rule is never consulted for this token at all.
  TFmxSole3b = class(TObject)
  private
    FSoleMarkFmx3b: Integer;
  published
    property SoleMarkFmx3b: Integer read FSoleMarkFmx3b write FSoleMarkFmx3b;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Vcl.SoleHost3b.pas') @'
unit Vcl.SoleHost3b;

interface

type
  TVclSoleHost3b = class(TObject)
  private
    FThing: TFmxSole3b;
  published
    property Thing: TFmxSole3b read FThing write FThing;
  end;

implementation

end.
'@

# CONTROL for case 3: identical shape, SAME namespace -- must still expand, so
# the refusal above cannot be a blanket "never recurse into a lone candidate".
Write-Ascii (Join-Path $work 'Vcl.SoleOk3b.pas') @'
unit Vcl.SoleOk3b;

interface

type
  TVclSoleOk3b = class(TObject)
  private
    FSoleMarkOk3b: Integer;
  published
    property SoleMarkOk3b: Integer read FSoleMarkOk3b write FSoleMarkOk3b;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Vcl.SoleOkHost3b.pas') @'
unit Vcl.SoleOkHost3b;

interface

type
  TVclSoleOkHost3b = class(TObject)
  private
    FThing: TVclSoleOk3b;
  published
    property Thing: TVclSoleOk3b read FThing write FThing;
  end;

implementation

end.
'@

# --- Case 4: the BRIDGED bare-property path (ResolveViaBridgedAncestry). ------
# 'BareMark3b' is redeclared BARE on a Vcl.* class; its type exists only above an
# unresolved type-ALIAS ancestor edge that leads to a lone FMX-declared class.
Write-Ascii (Join-Path $work 'FMX.BareBase3b.pas') @'
unit FMX.BareBase3b;

interface

type
  TFmxBareMarkType3b = (fbm3bA, fbm3bB);

  TFmxBareBase3b = class(TObject)
  private
    FBareMark3b: TFmxBareMarkType3b;
  published
    property BareMark3b: TFmxBareMarkType3b read FBareMark3b write FBareMark3b;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Vcl.Bare3b.pas') @'
unit Vcl.Bare3b;

interface

type
  // A type ALIAS ancestor: ResolveAncestry's candidate set is class/interface
  // only, so this edge is left UNRESOLVED and the bare property below can only
  // get a type through ResolveViaBridgedAncestry.
  TBareAlias3b = TFmxBareBase3b;

  TVclBare3b = class(TBareAlias3b)
  published
    property BareMark3b;
  end;

implementation

end.
'@

# CONTROL for case 4: identical shape, SAME namespace -- must still bridge.
Write-Ascii (Join-Path $work 'Vcl.BareOkBase3b.pas') @'
unit Vcl.BareOkBase3b;

interface

type
  TVclBareOkMarkType3b = (vbm3bA, vbm3bB);

  TVclBareOkBase3b = class(TObject)
  private
    FBareOkMark3b: TVclBareOkMarkType3b;
  published
    property BareOkMark3b: TVclBareOkMarkType3b read FBareOkMark3b write FBareOkMark3b;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Vcl.BareOk3b.pas') @'
unit Vcl.BareOk3b;

interface

type
  TBareOkAlias3b = TVclBareOkBase3b;

  TVclBareOk3b = class(TBareOkAlias3b)
  published
    property BareOkMark3b;
  end;

implementation

end.
'@

# --- Case 5/6: a LEGITIMATE namespace crossing must NOT be refused. -----------
# The cross-framework guard is Vcl-vs-FMX ONLY. 'System.*' is shared ground that
# every VCL unit references (TBasicAction, TList, TComponent, PResource, ...).
# An earlier revision of this task refused on ANY differing prefix and silently
# degraded all of those to 'scalar' on the real library. These two cases pin that
# shut, one per code path: the property type, and the ancestor chain.
Write-Ascii (Join-Path $work 'System.Cand3b.pas') @'
unit System.Cand3b;

interface

type
  // Globally unique name, so PickCandidate short-circuits and the shared scope
  // rule never runs -- the ONLY thing that can reject this is the guard.
  TSysOnly3b = class(TObject)
  private
    FSysMark3b: Integer;
  published
    property SysMark3b: Integer read FSysMark3b write FSysMark3b;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Vcl.SysHost3b.pas') @'
unit Vcl.SysHost3b;

interface

type
  // 'Vcl' referencing 'System' -- an ordinary RTL reference, not a framework
  // conflict. Must expand.
  TVclSysHost3b = class(TObject)
  private
    FThing: TSysOnly3b;
  published
    property Thing: TSysOnly3b read FThing write FThing;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'System.Base3b.pas') @'
unit System.Base3b;

interface

type
  TSysBase3b = class(TObject)
  private
    FSysBaseMark3b: Integer;
  published
    property SysBaseMark3b: Integer read FSysBaseMark3b write FSysBaseMark3b;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $work 'Vcl.SysDeriv3b.pas') @'
unit Vcl.SysDeriv3b;

interface

type
  // The CHAIN side of the same question: a Vcl.* class whose ancestor is only
  // reachable across an unresolved type-alias edge into System.*. Refusing this
  // was a latent defect in the Task 3 climb, for the same wrong reason.
  TSysAlias3b = TSysBase3b;

  TVclSysDeriv3b = class(TSysAlias3b)
  end;

implementation

end.
'@

$db = Join-Path $WorkDir 'proptypescope.sqlite'
Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>$null
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($indexOut -join ' | ')"

function Get-Tree([string]$QName) {
  Push-Location $WorkDir
  try {
    $raw = (& $Exe proptree --qname $QName --format json --db $db --no-write-back 2>$null) -join "`n"
  } finally { Pop-Location }
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
  return ($raw | ConvertFrom-Json)
}
function Get-Leaf($Tree, [string]$Path) {
  if ($null -eq $Tree) { return $null }
  return (@($Tree.properties) | Where-Object { $_.path -eq $Path } | Select-Object -First 1)
}
function Get-Paths($Tree) {
  if ($null -eq $Tree) { return '<no tree>' }
  return ((@($Tree.properties) | ForEach-Object { $_.path }) -join ', ')
}

# --- CASE 1 ------------------------------------------------------------------
Write-Host ''
Write-Host 'Case 1: ambiguous property type resolves per-framework, BOTH directions' -ForegroundColor Cyan
$t1v = Get-Tree 'Vcl.Host3b.TVclHost3b'
Check "fixture sanity: TVclHost3b resolves as a class" ($null -ne $t1v -and $t1v.root_type -eq 'TVclHost3b') "root_type=$($t1v.root_type)"
$thing1v = Get-Leaf $t1v 'Thing'
Check "TVclHost3b.Thing is class-typed (it must still be recursed into)" `
  ($null -ne $thing1v -and $thing1v.is_class_typed -eq $true) "type=$($thing1v.type) class_typed=$($thing1v.is_class_typed)"
Check "TVclHost3b.Thing expands the VCL TAmb3b ('Thing.MarkVcl3b' present)" `
  ($null -ne (Get-Leaf $t1v 'Thing.MarkVcl3b')) ("paths=" + (Get-Paths $t1v))
Check "TVclHost3b.Thing does NOT expand the FMX TAmb3b ('Thing.MarkFmx3b' absent)" `
  ($null -eq (Get-Leaf $t1v 'Thing.MarkFmx3b')) ("paths=" + (Get-Paths $t1v))

$t1f = Get-Tree 'FMX.Host3b.TFmxHost3b'
Check "fixture sanity: TFmxHost3b resolves as a class" ($null -ne $t1f -and $t1f.root_type -eq 'TFmxHost3b') "root_type=$($t1f.root_type)"
Check "TFmxHost3b.Thing expands the FMX TAmb3b ('Thing.MarkFmx3b' present)" `
  ($null -ne (Get-Leaf $t1f 'Thing.MarkFmx3b')) ("paths=" + (Get-Paths $t1f))
Check "TFmxHost3b.Thing does NOT expand the VCL TAmb3b ('Thing.MarkVcl3b' absent)" `
  ($null -eq (Get-Leaf $t1f 'Thing.MarkVcl3b')) ("paths=" + (Get-Paths $t1f))

# --- CASE 2 ------------------------------------------------------------------
Write-Host ''
Write-Host "Case 2: the scope is the DECLARING class's unit, not the queried root's (criterion 7)" -ForegroundColor Cyan
$t2v = Get-Tree 'Zed.Root3b.TZedRoot3b'
Check "fixture sanity: TZedRoot3b resolves as a class" ($null -ne $t2v -and $t2v.root_type -eq 'TZedRoot3b') "root_type=$($t2v.root_type)"
$thing2v = Get-Leaf $t2v 'Thing'
Check "fixture sanity: 'Thing' is inherited from Vcl.Mid3b.TVclMid3b (a DIFFERENT unit from the root)" `
  ($null -ne $thing2v -and $thing2v.declared_in -eq 'Vcl.Mid3b.TVclMid3b') "declared_in=$($thing2v.declared_in)"
Check "TZedRoot3b.Thing expands the VCL TAmb3b ('Thing.MarkVcl3b' present)" `
  ($null -ne (Get-Leaf $t2v 'Thing.MarkVcl3b')) `
  ("paths=" + (Get-Paths $t2v) + " -- ABSENT means the token was resolved in the ROOT unit 'Zed.Root3b', whose 'Zed' prefix matches no candidate, so the rule declined: that IS the criterion-7 defect one layer down")
Check "TZedRoot3b.Thing does NOT expand the FMX TAmb3b" `
  ($null -eq (Get-Leaf $t2v 'Thing.MarkFmx3b')) ("paths=" + (Get-Paths $t2v))

$t2f = Get-Tree 'Zed.Root3b.TZedRootF3b'
Check "fixture sanity: TZedRootF3b resolves as a class" ($null -ne $t2f -and $t2f.root_type -eq 'TZedRootF3b') "root_type=$($t2f.root_type)"
Check "TZedRootF3b.Thing expands the FMX TAmb3b ('Thing.MarkFmx3b' present) -- same root unit, opposite framework" `
  ($null -ne (Get-Leaf $t2f 'Thing.MarkFmx3b')) ("paths=" + (Get-Paths $t2f))
Check "TZedRootF3b.Thing does NOT expand the VCL TAmb3b" `
  ($null -eq (Get-Leaf $t2f 'Thing.MarkVcl3b')) ("paths=" + (Get-Paths $t2f))

# --- CASE 3 ------------------------------------------------------------------
Write-Host ''
Write-Host 'Case 3: a LONE cross-namespace candidate is refused (criterion 5, no scope rule runs)' -ForegroundColor Cyan
$t3 = Get-Tree 'Vcl.SoleHost3b.TVclSoleHost3b'
Check "fixture sanity: TVclSoleHost3b resolves as a class" ($null -ne $t3 -and $t3.root_type -eq 'TVclSoleHost3b') "root_type=$($t3.root_type)"
$thing3 = Get-Leaf $t3 'Thing'
Check "fixture sanity: 'Thing' is still emitted, typed as written" `
  ($null -ne $thing3 -and $thing3.type -eq 'TFmxSole3b') "type=$($thing3.type)"
Check "Vcl.* class does NOT recurse into the lone FMX.* class ('Thing.SoleMarkFmx3b' absent)" `
  ($null -eq (Get-Leaf $t3 'Thing.SoleMarkFmx3b')) `
  ("paths=" + (Get-Paths $t3) + " -- PRESENT means a Vcl class expanded an FMX property surface with no scope check at all, because PickCandidate short-circuits on the lone candidate")
Check "the refused leaf degrades to 'scalar', not to a fabricated type" `
  ($null -ne $thing3 -and $thing3.kind -eq 'scalar' -and $thing3.is_class_typed -eq $false) "kind=$($thing3.kind) class_typed=$($thing3.is_class_typed)"

$t3ok = Get-Tree 'Vcl.SoleOkHost3b.TVclSoleOkHost3b'
Check "control: the SAME shape with a same-namespace lone candidate STILL expands" `
  ($null -ne (Get-Leaf $t3ok 'Thing.SoleMarkOk3b')) ("paths=" + (Get-Paths $t3ok))

# --- CASE 4 ------------------------------------------------------------------
Write-Host ''
Write-Host 'Case 4: the BRIDGED bare-property path refuses a cross-namespace type too' -ForegroundColor Cyan
$t4 = Get-Tree 'Vcl.Bare3b.TVclBare3b'
Check "fixture sanity: TVclBare3b resolves as a class" ($null -ne $t4 -and $t4.root_type -eq 'TVclBare3b') "root_type=$($t4.root_type)"
$bare4 = Get-Leaf $t4 'BareMark3b'
Check "fixture sanity: the bare 'BareMark3b' leaf is emitted at all" ($null -ne $bare4) ("paths=" + (Get-Paths $t4))
Check "bare property does NOT take its type from the lone FMX class across the alias edge" `
  ($null -ne $bare4 -and $bare4.type -ne 'TFmxBareMarkType3b') `
  ("type=$($bare4.type) -- 'TFmxBareMarkType3b' means ResolveViaBridgedAncestry.Climb bridged a Vcl.* class to an FMX.* one, the gap ClassChain.ClimbFrom already guards but this path did not")
Check "bare property stays 'unknown' (a genuine decline, not a different guess)" `
  ($null -ne $bare4 -and $bare4.type -eq 'unknown') "type=$($bare4.type)"

$t4ok = Get-Tree 'Vcl.BareOk3b.TVclBareOk3b'
$bare4ok = Get-Leaf $t4ok 'BareOkMark3b'
Check "control: the SAME shape with a same-namespace target STILL bridges the bare type" `
  ($null -ne $bare4ok -and $bare4ok.type -eq 'TVclBareOkMarkType3b') "type=$($bare4ok.type)"

# --- CASE 5 ------------------------------------------------------------------
Write-Host ''
Write-Host 'Case 5: a Vcl.* class STILL expands a System.*-typed property (guard is Vcl-vs-FMX only)' -ForegroundColor Cyan
$t5 = Get-Tree 'Vcl.SysHost3b.TVclSysHost3b'
Check "fixture sanity: TVclSysHost3b resolves as a class" ($null -ne $t5 -and $t5.root_type -eq 'TVclSysHost3b') "root_type=$($t5.root_type)"
$thing5 = Get-Leaf $t5 'Thing'
Check "TVclSysHost3b.Thing is class-typed" ($null -ne $thing5 -and $thing5.is_class_typed -eq $true) `
  "type=$($thing5.type) kind=$($thing5.kind) class_typed=$($thing5.is_class_typed)"
Check "TVclSysHost3b.Thing expands the System.* class ('Thing.SysMark3b' present)" `
  ($null -ne (Get-Leaf $t5 'Thing.SysMark3b')) `
  ("paths=" + (Get-Paths $t5) + " -- ABSENT means the cross-framework guard was widened into a blanket different-namespace veto, which on the real library degrades every RTL-typed VCL property (TBasicAction, TList, TComponent, PResource) to 'scalar'")

# --- CASE 6 ------------------------------------------------------------------
Write-Host ''
Write-Host 'Case 6: the ancestor CHAIN also still bridges Vcl.* -> System.*' -ForegroundColor Cyan
$t6 = Get-Tree 'Vcl.SysDeriv3b.TVclSysDeriv3b'
Check "fixture sanity: TVclSysDeriv3b resolves as a class" ($null -ne $t6 -and $t6.root_type -eq 'TVclSysDeriv3b') "root_type=$($t6.root_type)"
$sys6 = Get-Leaf $t6 'SysBaseMark3b'
Check "Vcl.* class inherits its System.* ancestor's property across the alias edge" ($null -ne $sys6) `
  ("paths=" + (Get-Paths $t6) + " -- ABSENT means ClassChain.ClimbFrom refused a legitimate Vcl->System bridge")
Check "and that inherited property is attributed to the System.* declarer" `
  ($null -ne $sys6 -and $sys6.declared_in -eq 'System.Base3b.TSysBase3b') "declared_in=$($sys6.declared_in)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
