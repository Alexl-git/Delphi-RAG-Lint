<#
  run_proptree_visibility.ps1 -- proptree/2 schema + R2 EFFECTIVE visibility +
  --min-visibility (Track 3, proptree assignability engine, Task 2).

  TASK 2 adds three new per-leaf fields to the proptree JSON (visibility,
  is_writable, member_kind), bumps the top-level schema to 'proptree/2', and
  adds a --min-visibility published|public CLI filter. is_writable is
  HARD-CODED true and member_kind defaults 'property' in this task (R1/a later
  task fill real writability/member-kind); only EFFECTIVE visibility is real.

  EFFECTIVE VISIBILITY = the MOST-DERIVED declaration wins (mirrors the
  existing DeclaredIn resolution). A published re-declaration of a
  protected/public ancestor property RAISES its effective visibility to
  published -- the classic Delphi re-publish idiom ('property Align;' under a
  `published` section).

  FIXTURE (VisFix.pas, one ancestor chain TDerived(TMid(TBase))):
    TBase   -- own properties at all four levels:
                 private   PrivName: string
                 protected ProtValue: Integer
                 public    PubFlag: Boolean
                 published PubName: string
    TMid    -- no redeclarations (pure pass-through link in the chain).
    TDerived -- 'published property ProtValue;' -- a BARE redeclaration that
                RAISES TBase's protected ProtValue to published. This is the
                load-bearing case: the effective visibility must come from
                TDerived's OWN declSection (published), not TBase's
                (protected), even though the type must still be resolved by
                walking up to TBase (empty signature).

  Load-bearing assertions (proptree --qname VisFix.TDerived --format json):
    - schema == 'proptree/2' (was 'proptree/1')
    - no --min-visibility: ALL 4 leaves present (back-compat: default = show
      everything), each leaf carries its raw 'visibility' string, every leaf
      has is_writable == true and member_kind == 'property'
    - PrivName.visibility   == 'private'
    - PubFlag.visibility    == 'public'
    - PubName.visibility    == 'published'
    - ProtValue.visibility  == 'published'  (RAISED from TBase's 'protected'
      -- THE regression guard for effective-visibility resolution)
    - ProtValue.type == 'Integer' (still resolves the bare redeclaration's
      type via the pre-existing ancestor walk; visibility resolution must not
      break type resolution)
    - --min-visibility published -> exactly {ProtValue, PubName} (2 leaves),
      every emitted leaf's visibility == 'published'
    - --min-visibility public -> exactly {ProtValue, PubName, PubFlag}
      (3 leaves; adds PubFlag, still excludes PrivName), every emitted leaf's
      visibility is 'published' or 'public'

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-proptree-visibility by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-proptree-visibility"
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

Write-Ascii (Join-Path $work 'VisFix.pas') @'
unit VisFix;

interface

type
  TBase = class(TPersistent)
  private
    FPrivName: string;
    FProtValue: Integer;
    FPubFlag: Boolean;
    FPubName: string;
  private
    property PrivName: string read FPrivName write FPrivName;
  protected
    property ProtValue: Integer read FProtValue write FProtValue;
  public
    property PubFlag: Boolean read FPubFlag write FPubFlag;
  published
    property PubName: string read FPubName write FPubName;
  end;

  TMid = class(TBase)
  end;

  TDerived = class(TMid)
  published
    property ProtValue;   // bare redeclaration RAISING visibility: protected -> published
  end;

implementation

end.
'@

$db = Join-Path $WorkDir 'visfix.sqlite'
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

# --- 1. No --min-visibility: back-compat, ALL leaves, schema bump, new fields. ----
Write-Host ''
Write-Host 'proptree VisFix.TDerived (no --min-visibility)' -ForegroundColor Cyan
$r = Get-Tree $db 'VisFix.TDerived'
Check 'proptree exits 0' ($r.Exit -eq 0) "exit=$($r.Exit)"
Check 'proptree --format json parses as JSON' ($null -ne $r.Tree) "raw=$($r.Raw)"

if ($null -ne $r.Tree) {
  $tree = $r.Tree
  Check "schema is 'proptree/2'" ($tree.schema -eq 'proptree/2') "schema=$($tree.schema)"

  $props = @($tree.properties)
  $byPath = @{}
  foreach ($p in $props) { $byPath[$p.path] = $p }
  $paths = @($props | ForEach-Object { $_.path })

  Check 'no flag: all 4 leaves present' ($props.Count -eq 4) ("paths=" + ($paths -join ', '))
  Check "has 'PrivName'"  ($byPath.ContainsKey('PrivName'))
  Check "has 'ProtValue'" ($byPath.ContainsKey('ProtValue'))
  Check "has 'PubFlag'"   ($byPath.ContainsKey('PubFlag'))
  Check "has 'PubName'"   ($byPath.ContainsKey('PubName'))

  if ($byPath.ContainsKey('PrivName')) {
    Check "PrivName.visibility == 'private'" ($byPath['PrivName'].visibility -eq 'private') "visibility=$($byPath['PrivName'].visibility)"
  }
  if ($byPath.ContainsKey('PubFlag')) {
    Check "PubFlag.visibility == 'public'" ($byPath['PubFlag'].visibility -eq 'public') "visibility=$($byPath['PubFlag'].visibility)"
  }
  if ($byPath.ContainsKey('PubName')) {
    Check "PubName.visibility == 'published'" ($byPath['PubName'].visibility -eq 'published') "visibility=$($byPath['PubName'].visibility)"
  }
  if ($byPath.ContainsKey('ProtValue')) {
    $pv = $byPath['ProtValue']
    Check "ProtValue.visibility == 'published' (RAISED from TBase's protected)" ($pv.visibility -eq 'published') "visibility=$($pv.visibility)"
    Check "ProtValue.type == 'Integer' (ancestor-walk type resolution still works)" ($pv.type -eq 'Integer') "type=$($pv.type)"
  } else {
    Check "ProtValue node present" $false ''
  }

  $allWritableTrue  = -not ($props | Where-Object { $_.is_writable -ne $true })
  $allMemberKindProp = -not ($props | Where-Object { $_.member_kind -ne 'property' })
  Check 'every leaf has is_writable == true'        $allWritableTrue  ("values=" + (($props | ForEach-Object { $_.is_writable }) -join ', '))
  Check "every leaf has member_kind == 'property'"  $allMemberKindProp ("values=" + (($props | ForEach-Object { $_.member_kind }) -join ', '))
}

# --- 2. --min-visibility published -> only published leaves. ----------------------
Write-Host ''
Write-Host 'proptree VisFix.TDerived --min-visibility published' -ForegroundColor Cyan
$rp = Get-Tree $db 'VisFix.TDerived' 'published'
Check '--min-visibility published: exits 0' ($rp.Exit -eq 0) "exit=$($rp.Exit)"
if ($null -ne $rp.Tree) {
  $pprops = @($rp.Tree.properties)
  $ppaths = @($pprops | ForEach-Object { $_.path })
  Check '--min-visibility published: exactly 2 leaves' ($pprops.Count -eq 2) ("paths=" + ($ppaths -join ', '))
  Check '--min-visibility published: contains ProtValue' ($ppaths -contains 'ProtValue') ("paths=" + ($ppaths -join ', '))
  Check '--min-visibility published: contains PubName'   ($ppaths -contains 'PubName')   ("paths=" + ($ppaths -join ', '))
  Check '--min-visibility published: excludes PubFlag'   (-not ($ppaths -contains 'PubFlag'))
  Check '--min-visibility published: excludes PrivName'  (-not ($ppaths -contains 'PrivName'))
  $allPublished = -not ($pprops | Where-Object { $_.visibility -ne 'published' })
  Check '--min-visibility published: every leaf visibility == published' $allPublished ("values=" + (($pprops | ForEach-Object { $_.visibility }) -join ', '))
} else {
  Check '--min-visibility published: --format json parses as JSON' $false "raw=$($rp.Raw)"
}

# --- 3. --min-visibility public -> published + public leaves. ---------------------
Write-Host ''
Write-Host 'proptree VisFix.TDerived --min-visibility public' -ForegroundColor Cyan
$rpub = Get-Tree $db 'VisFix.TDerived' 'public'
Check '--min-visibility public: exits 0' ($rpub.Exit -eq 0) "exit=$($rpub.Exit)"
if ($null -ne $rpub.Tree) {
  $pubprops = @($rpub.Tree.properties)
  $pubpaths = @($pubprops | ForEach-Object { $_.path })
  Check '--min-visibility public: exactly 3 leaves' ($pubprops.Count -eq 3) ("paths=" + ($pubpaths -join ', '))
  Check '--min-visibility public: contains ProtValue' ($pubpaths -contains 'ProtValue') ("paths=" + ($pubpaths -join ', '))
  Check '--min-visibility public: contains PubName'   ($pubpaths -contains 'PubName')   ("paths=" + ($pubpaths -join ', '))
  Check '--min-visibility public: contains PubFlag'   ($pubpaths -contains 'PubFlag')   ("paths=" + ($pubpaths -join ', '))
  Check '--min-visibility public: excludes PrivName'  (-not ($pubpaths -contains 'PrivName'))
  $allPubOrPublished = -not ($pubprops | Where-Object { ($_.visibility -ne 'published') -and ($_.visibility -ne 'public') })
  Check '--min-visibility public: every leaf visibility is published or public' $allPubOrPublished ("values=" + (($pubprops | ForEach-Object { $_.visibility }) -join ', '))
} else {
  Check '--min-visibility public: --format json parses as JSON' $false "raw=$($rpub.Raw)"
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
