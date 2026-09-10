<#
  run_proptree_duplicate_copy_guard.ps1 -- Option B of
  docs\PLAN-proptree-tcomponent-members.md: when a candidate set reaching
  PickAncestorCandidateByScope contains several CONTENT-IDENTICAL copies of one
  declaration, they are collapsed to a single candidate before the rules run.

  WHY THIS EXISTS -- the defect it pins is a DATA shape, not a rule bug.
  library-Win32.sqlite holds the DevExpress source tree TWICE, because the Win32
  registry Search Path lists $(DXVCL)\Library\RS37 -- the PARENT of DevExpress's
  per-platform folders -- and the indexer walks a library root RECURSIVELY (the
  compiler does not). Every DevExpress class then has a same-qualified-name twin
  in a second file. The scope rule cannot tell the two apart -- same declaring
  unit, so pass 2a scores UsesHits = 2 and falls through BY DESIGN ("never settle
  by order"); undotted unit names give rule 3 no segment -- so it DECLINES, and
  the ancestry chain of TcxGrid breaks at TcxCustomGrid -> TcxControl, four hops
  below TComponent. Measured 2026-09-09: TcxGrid had 103 top-level members on
  Win32 against 471 on Win64, with Name and Tag ABSENT.

  Declining is the CORRECT answer for two candidates that genuinely differ. It is
  the wrong answer for two candidates that are the same declaration reached by two
  paths. This guard pins that distinction, and specifically pins that the fix did
  NOT weaken the decline into "take the first one".

  FIXTURE (the plan's, reproducing the real shape without needing DevExpress):
    lib\Base\BaseKit.pas       TBaseKit  = class(TObject)  published Name, Tag
    lib\Sources\MidKit.pas     TMidKit   = class(TBaseKit) published Marker: TMarkA
    lib\WinArm64EC\MidKit.pas  BYTE-IDENTICAL copy of lib\Sources\MidKit.pas
    app\RootKit.pas            TRootKit  = class(TMidKit)  published property Marker;

  RootKit `uses MidKit`, and BOTH copies declare unit MidKit, so rule 2a hits
  twice and falls through; RootKit is undotted so rule 3 has no segment; the
  edge declines. Name/Tag (two hops up, in TBaseKit) then never reach TRootKit,
  and the bare `property Marker;` cannot bridge. That is the whole defect, in
  four files.

  CASES
    precondition  MidKit.TMidKit really does have TWO class rows with identical
                  heritage and identical (start_line, end_line). ASSERTED, not
                  assumed: if the parser or the walk ever dedupes upstream, this
                  fails loudly instead of leaving CASE A vacuously green.
    A             the defect. Name is a top-level leaf declared in BaseKit.TBaseKit,
                  and Marker resolves to TMarkA.
    P             POSITIVE CONTROL. Same fixture WITHOUT the second copy. Must pass
                  on the PRE-FIX exe too -- that is what proves the fixture is
                  sound and the duplicate copy is the only variable. Without this,
                  a fixture that was broken for some unrelated reason would show
                  the same two red lines as the real defect.
    N             NEGATIVE CONTROL. The second copy is NOT identical (different
                  ancestor and a different Marker type). Must STILL decline:
                  Marker unknown, Name absent, and never the decoy's type. This is
                  what stops a "just take the first candidate" patch from passing,
                  and it is why the collapse keys on CONTENT (heritage + span)
                  rather than on identity.

  RED SIGNATURE -- observed against the PRE-FIX engine before the fix existed,
  commit b137bf5 (snapshot sha256 1F24617176B8607D1EF09866987C4DD3E884C930F1B52581273AEFA6D0901A59):

    [PASS] precondition: MidKit.TMidKit has exactly 2 class rows
    [PASS] precondition: the 2 rows have identical heritage
    [PASS] precondition: the 2 rows have identical span
    [FAIL] CASE A: 'Name' is a top-level leaf of RootKit.TRootKit   got: ABSENT
    [FAIL] CASE A: 'Name' is declared in BaseKit.TBaseKit           got: ABSENT
    [FAIL] CASE A: 'Tag' is a top-level leaf of RootKit.TRootKit    got: ABSENT
    [FAIL] CASE A: Marker resolves to 'TMarkA'                      got: unknown
    [PASS] CASE P: single copy -- 'Name' is present
    [PASS] CASE P: single copy -- Marker resolves to 'TMarkA'
    [PASS] CASE N: differing copies -- Marker still declines
    [PASS] CASE N: differing copies -- 'Name' still absent
    [PASS] CASE N: differing copies -- Marker is NOT the decoy type
    FAIL

  FOUR fail lines, all in CASE A. Anything else -- a failing precondition, or a
  red line in P or N -- means the FIXTURE is being measured, not the engine.
  Stop and fix the fixture before touching src.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-proptree-duplicate-copy"
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

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# --- the four fixture units --------------------------------------------------

$baseKit = @'
unit BaseKit;

interface

type
  TBaseKit = class(TObject)
  private
    FName: string;
    FTag : Integer;
  published
    property Name: string read FName write FName;
    property Tag : Integer read FTag write FTag;
  end;

implementation

end.
'@

$midKit = @'
unit MidKit;

interface

uses
  BaseKit;

type
  TMarkA = (mkA1, mkA2);

  TMidKit = class(TBaseKit)
  private
    FMarker: TMarkA;
  published
    property Marker: TMarkA read FMarker write FMarker;
  end;

implementation

end.
'@

# CASE N's second copy: same unit name and same class name, DIFFERENT content --
# a different ancestor and a different Marker type. Must never collapse.
$midKitDecoy = @'
unit MidKit;

interface

type
  TMarkDecoy = (mkD1, mkD2);

  TDecoyKit = class(TObject)
  end;

  TMidKit = class(TDecoyKit)
  private
    FMarker: TMarkDecoy;
  published
    property Marker: TMarkDecoy read FMarker write FMarker;
  end;

implementation

end.
'@

$rootKit = @'
unit RootKit;

interface

uses
  MidKit;

type
  TRootKit = class(TMidKit)
  published
    property Marker;
  end;

implementation

end.
'@

# --- helpers -----------------------------------------------------------------

# stdout and stderr are redirected SEPARATELY, never merged. Session 84 lost an
# afternoon to a stderr line being cut in half mid-path and a stdout line spliced
# into the gap, which broke a line-anchored regex and presented as a mysterious
# CWD dependency. The engine writes '(loaded defaults from ...)' to stderr during
# these very commands.
function Invoke-Json([string[]]$DragArgs) {
  $raw = (& $Exe @DragArgs 2>$null) -join "`n"
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
  return $raw | ConvertFrom-Json
}

function Build-Db([string]$Name, [hashtable]$Files) {
  $work = Join-Path $WorkDir $Name
  foreach ($rel in $Files.Keys) { Write-Ascii (Join-Path $work $rel) $Files[$rel] }
  $db = Join-Path $WorkDir "$Name.sqlite"
  $out = & $Exe index $work --db $db 2>$null
  Check "$Name`: index exits 0" ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE; $($out -join ' | ')"
  return $db
}

# Returns the proptree property whose path is exactly $Path (top level = no dot),
# or $null when it is absent.
function Get-Prop([string]$Database, [string]$QName, [string]$Path) {
  $tree = Invoke-Json @('proptree', '--qname', $QName, '--format', 'json', '--db', $Database, '--no-write-back')
  if ($null -eq $tree) { return $null }
  return @($tree.properties) | Where-Object { $_.path -eq $Path } | Select-Object -First 1
}

function Describe($Prop, [string]$Field) {
  if ($null -eq $Prop) { return 'ABSENT' }
  return [string]$Prop.$Field
}

# --- CASE A: two byte-identical copies ---------------------------------------

Write-Host ''
Write-Host 'CASE A: two byte-identical copies of MidKit' -ForegroundColor Cyan

$dbA = Build-Db 'A' @{
  'lib\Base\BaseKit.pas'      = $baseKit
  'lib\Sources\MidKit.pas'    = $midKit
  'lib\WinArm64EC\MidKit.pas' = $midKit
  'app\RootKit.pas'           = $rootKit
}

# Precondition, asserted rather than assumed.
$rows = @(Invoke-Json @('query', '--qname', 'MidKit.TMidKit', '--json', '--db', $dbA)) |
        Where-Object { $_.kind -eq 'class' }
Check 'precondition: MidKit.TMidKit has exactly 2 class rows' ($rows.Count -eq 2) "count=$($rows.Count)"
if ($rows.Count -eq 2) {
  $sameHeritage = ($rows[0].heritage.Trim() -ieq $rows[1].heritage.Trim())
  $sameSpan     = ($rows[0].start_line -eq $rows[1].start_line) -and
                  ($rows[0].end_line   -eq $rows[1].end_line)
  Check 'precondition: the 2 rows have identical heritage' $sameHeritage "'$($rows[0].heritage)' vs '$($rows[1].heritage)'"
  Check 'precondition: the 2 rows have identical span' $sameSpan "($($rows[0].start_line)-$($rows[0].end_line)) vs ($($rows[1].start_line)-$($rows[1].end_line))"
  Check 'precondition: the 2 rows are in DIFFERENT files' ($rows[0].file_id -ne $rows[1].file_id) "file_id $($rows[0].file_id) vs $($rows[1].file_id)"
}

$aName   = Get-Prop $dbA 'RootKit.TRootKit' 'Name'
$aTag    = Get-Prop $dbA 'RootKit.TRootKit' 'Tag'
$aMarker = Get-Prop $dbA 'RootKit.TRootKit' 'Marker'

Check "CASE A: 'Name' is a top-level leaf of RootKit.TRootKit" ($null -ne $aName) "got: $(Describe $aName 'path')"
Check "CASE A: 'Name' is declared in BaseKit.TBaseKit" ((Describe $aName 'declared_in') -eq 'BaseKit.TBaseKit') "got: $(Describe $aName 'declared_in')"
Check "CASE A: 'Tag' is a top-level leaf of RootKit.TRootKit" ($null -ne $aTag) "got: $(Describe $aTag 'path')"
Check "CASE A: Marker resolves to 'TMarkA'" ((Describe $aMarker 'type') -eq 'TMarkA') "got: $(Describe $aMarker 'type')"

# --- CASE P: positive control, single copy -----------------------------------

Write-Host ''
Write-Host 'CASE P (positive control): a single copy must work on ANY build' -ForegroundColor Cyan

$dbP = Build-Db 'P' @{
  'lib\Base\BaseKit.pas'   = $baseKit
  'lib\Sources\MidKit.pas' = $midKit
  'app\RootKit.pas'        = $rootKit
}

$pName   = Get-Prop $dbP 'RootKit.TRootKit' 'Name'
$pMarker = Get-Prop $dbP 'RootKit.TRootKit' 'Marker'
Check "CASE P: single copy -- 'Name' is present" ($null -ne $pName) "got: $(Describe $pName 'path')"
Check "CASE P: single copy -- Marker resolves to 'TMarkA'" ((Describe $pMarker 'type') -eq 'TMarkA') "got: $(Describe $pMarker 'type')"

# --- CASE N: negative control, copies that genuinely differ ------------------

Write-Host ''
Write-Host 'CASE N (negative control): differing copies must STILL decline' -ForegroundColor Cyan

$dbN = Build-Db 'N' @{
  'lib\Base\BaseKit.pas'      = $baseKit
  'lib\Sources\MidKit.pas'    = $midKit
  'lib\WinArm64EC\MidKit.pas' = $midKitDecoy
  'app\RootKit.pas'           = $rootKit
}

$nName   = Get-Prop $dbN 'RootKit.TRootKit' 'Name'
$nMarker = Get-Prop $dbN 'RootKit.TRootKit' 'Marker'
$nType   = Describe $nMarker 'type'
Check "CASE N: differing copies -- Marker still declines" ($nType -eq 'unknown') "got: $nType"
Check "CASE N: differing copies -- 'Name' still absent" ($null -eq $nName) "got: $(Describe $nName 'declared_in')"
Check "CASE N: differing copies -- Marker is NOT the decoy type" ($nType -ne 'TMarkDecoy') "got: $nType"
Check "CASE N: differing copies -- Marker is NOT 'TMarkA' either" ($nType -ne 'TMarkA') "got: $nType"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
