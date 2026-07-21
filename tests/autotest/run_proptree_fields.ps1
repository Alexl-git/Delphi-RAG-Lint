<#
  run_proptree_fields.ps1 -- proptree R4 public FIELDS as targets (Track 3,
  proptree assignability engine, Task 4).

  TASK 4 extends CollectProps/Walk (src/report/DRagLint.Convert.PropTree.pas)
  to ALSO emit leaves for a class's own PUBLIC/PUBLISHED skField members (a
  plain `public FThing: Integer;` field) so PAS-surface conversions can target
  fields, not just properties. member_kind='field' for every field/const leaf
  (was 'property'-only through Task 3).

  WRITABILITY (field-scoped, does NOT touch the staged property is_writable):
  a field is_writable=true EXCEPT a typed class CONSTANT (`const KMax: T =
  v;` inside a class), which is is_writable=false (Object Pascal consts are
  never assignable). Investigation of the index (empirical: indexed the
  fixture into a temp DB and inspected the `symbols` rows) confirmed a plain
  field and a class const are DIFFERENT SymbolKinds -- kind='field' vs
  kind='const' -- so the read-only determination is a clean kind check.

  VISIBILITY GAP (documented, not hidden): the indexer's declConst parser
  handler never stamps a Modifiers value for class consts (verified
  empirically -- every const row's `modifiers` column is '' regardless of its
  declared visibility section), unlike declField/declProp which both DO carry
  accurate Modifiers. PropTree.pas works ONLY from already-indexed data (no
  re-index, no raw-source access) -- see the implementation's
  ResolveConstVisibilityByProximity for how a const's effective visibility is
  recovered from its nearest visibility-bearing sibling.

  FIXTURE (FieldFix.pas, single class TFieldFix(TPersistent)):
    private   FPrivate: Integer;        -- must be ABSENT from every leaf list
    public    FThing:   Integer;        -- must appear as member_kind='field',
                                            is_writable=true
    public    const KMax: Integer = 5;  -- must appear, is_writable=false,
                                            member_kind='field'. NOTE: KMax.type
                                            resolves to 'unknown', NOT 'Integer'
                                            -- the parser's declConst branch
                                            never captures a Signature (see
                                            PropTree.pas/ResolveConstVisibility-
                                            ByProximity's comment), so this is a
                                            known, documented data gap, not an
                                            oversight in this test.
    published FBtn: TObject;            -- REVIEW FIX (spec-compliance): a
                                            published FIELD is legal Delphi
                                            (`published FBtn: TButton;`) and
                                            gets Modifiers='published' stamped
                                            by the same declField path a
                                            published PROPERTY gets. It must
                                            still be ABSENT under
                                            --min-visibility published (fields
                                            are never DFM-streamable proptree
                                            targets, regardless of their own
                                            declared visibility) while its
                                            EMITTED visibility stays the real,
                                            unclamped 'published' string under
                                            --min-visibility public.

  Load-bearing assertions (proptree --qname FieldFix.TFieldFix --format json):
    --min-visibility public:
      - FThing leaf present, member_kind == 'field', is_writable == true
      - KMax   leaf present, is_writable == false, member_kind == 'field'
      - FBtn   leaf present, member_kind == 'field', visibility == 'published'
        (REAL value, NOT clamped to 'public' -- the filter excludes it from
        the published TIER without altering what it reports)
      - FPrivate leaf ABSENT
    --min-visibility published:
      - NO field/const leaves at all -- FThing, KMax, AND FBtn are ALL
        excluded. FBtn is the load-bearing case: despite its own Modifiers
        being 'published', member_kind='field' categorically bars it from
        the 'published' tier (PassesMinVisibility in DRagLint.CLI.pas checks
        member_kind before the visibility string).

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-proptree-fields by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-proptree-fields"
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

Write-Ascii (Join-Path $work 'FieldFix.pas') @'
unit FieldFix;

interface

type
  TFieldFix = class(TPersistent)
  private
    FPrivate: Integer;
  public
    FThing: Integer;
    const KMax: Integer = 5;
  published
    FBtn: TObject;
  end;

implementation

end.
'@

$db = Join-Path $WorkDir 'fieldfix.sqlite'
Write-Host 'Indexing fixture' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
$indexExit = $LASTEXITCODE
Check 'index exits 0' ($indexExit -eq 0) "exit=$indexExit; $($indexOut -join ' | ')"

function Get-Tree([string]$Database, [string]$QName, [string]$MinVis = '') {
  Push-Location $WorkDir
  try {
    if ($MinVis -ne '') {
      $raw = (& $Exe proptree --qname $QName --min-visibility $MinVis --format json --db $Database) -join "`n"
    } else {
      $raw = (& $Exe proptree --qname $QName --format json --db $Database) -join "`n"
    }
    $exit = $LASTEXITCODE
  } finally { Pop-Location }
  $tree = $null
  try { $tree = $raw | ConvertFrom-Json } catch { }
  return @{ Tree = $tree; Exit = $exit; Raw = $raw }
}

# --- 1. --min-visibility public: FThing (field, writable) + KMax (const, read-only)
#        + FBtn (published-section field, REAL visibility preserved) present;
#        FPrivate absent. ----------------------------------------------------------
Write-Host ''
Write-Host 'proptree FieldFix.TFieldFix --min-visibility public' -ForegroundColor Cyan
$rpub = Get-Tree $db 'FieldFix.TFieldFix' 'public'
Check '--min-visibility public: exits 0' ($rpub.Exit -eq 0) "exit=$($rpub.Exit)"
Check '--min-visibility public: --format json parses as JSON' ($null -ne $rpub.Tree) "raw=$($rpub.Raw)"

if ($null -ne $rpub.Tree) {
  $props = @($rpub.Tree.properties)
  $byPath = @{}
  foreach ($p in $props) { $byPath[$p.path] = $p }
  $paths = @($props | ForEach-Object { $_.path })

  Check "has 'FThing'" ($byPath.ContainsKey('FThing')) ("paths=" + ($paths -join ', '))
  Check "has 'KMax'"   ($byPath.ContainsKey('KMax'))   ("paths=" + ($paths -join ', '))
  Check "has 'FBtn'"   ($byPath.ContainsKey('FBtn'))   ("paths=" + ($paths -join ', '))
  Check "excludes 'FPrivate'" (-not ($paths -contains 'FPrivate')) ("paths=" + ($paths -join ', '))

  if ($byPath.ContainsKey('FThing')) {
    $ft = $byPath['FThing']
    Check "FThing.member_kind == 'field'" ($ft.member_kind -eq 'field') "member_kind=$($ft.member_kind)"
    Check "FThing.is_writable == true"    ($ft.is_writable -eq $true)   "is_writable=$($ft.is_writable)"
  }
  if ($byPath.ContainsKey('KMax')) {
    $km = $byPath['KMax']
    Check "KMax.is_writable == false"   ($km.is_writable -eq $false) "is_writable=$($km.is_writable)"
    Check "KMax.member_kind == 'field'" ($km.member_kind -eq 'field') "member_kind=$($km.member_kind)"
  }
  if ($byPath.ContainsKey('FBtn')) {
    $fb = $byPath['FBtn']
    # REVIEW FIX load-bearing case: under --min-visibility public, a
    # published-section field is PRESENT (public tier includes published-
    # or-more-visible), member_kind='field', and its REAL declared
    # visibility ('published') must be reported UNCLAMPED -- the filter
    # excludes it from the 'published' TIER (checked below), it never
    # rewrites the emitted value.
    Check "FBtn.member_kind == 'field'"        ($fb.member_kind -eq 'field')     "member_kind=$($fb.member_kind)"
    Check "FBtn.visibility == 'published' (real, unclamped)" ($fb.visibility -eq 'published') "visibility=$($fb.visibility)"
  }
} else {
  Check '--min-visibility public: FThing present' $false ''
  Check '--min-visibility public: KMax present'   $false ''
  Check '--min-visibility public: FBtn present'   $false ''
}

# --- 2. --min-visibility published: NO field/const leaves at all -- INCLUDING
#        FBtn, whose own declared visibility IS 'published'. This is the
#        load-bearing regression guard for the review fix: member_kind='field'
#        must categorically bar a leaf from the 'published' tier regardless of
#        its own Visibility string. ------------------------------------------
Write-Host ''
Write-Host 'proptree FieldFix.TFieldFix --min-visibility published' -ForegroundColor Cyan
$rp = Get-Tree $db 'FieldFix.TFieldFix' 'published'
Check '--min-visibility published: exits 0' ($rp.Exit -eq 0) "exit=$($rp.Exit)"
if ($null -ne $rp.Tree) {
  $pprops = @($rp.Tree.properties)
  $ppaths = @($pprops | ForEach-Object { $_.path })
  $fieldLeaves = @($pprops | Where-Object { $_.member_kind -eq 'field' })
  Check '--min-visibility published: no member_kind=field leaves' ($fieldLeaves.Count -eq 0) ("paths=" + ($ppaths -join ', '))
  Check '--min-visibility published: excludes FThing' (-not ($ppaths -contains 'FThing')) ("paths=" + ($ppaths -join ', '))
  Check '--min-visibility published: excludes KMax'   (-not ($ppaths -contains 'KMax'))   ("paths=" + ($ppaths -join ', '))
  Check "--min-visibility published: excludes FBtn (published-section FIELD still barred)" (-not ($ppaths -contains 'FBtn')) ("paths=" + ($ppaths -join ', '))
} else {
  Check '--min-visibility published: --format json parses as JSON' $false "raw=$($rp.Raw)"
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
