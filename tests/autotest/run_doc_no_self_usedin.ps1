<#
  run_doc_no_self_usedin.ps1 -- Bug D regression (twin of Bug C's run_doc_no_self_
  caller.ps1): the "Used in units:" doc fact gather (DRagLint.Doc.Facts.pas, the
  skClass/skInterface/skRecord block) must NOT count a class's OWN qualified
  method-header self-reference as a unit that "uses" the class.

  ROOT CAUSE (fixed by this test): a qualified implementation header like
  'procedure TSelfOnly.Add;' emits a type_use ref of name_text='TSelfOnly' whose
  enclosing_symbol_id is the method itself (TSelfOnly.Add). Before the fix, the
  "Used in units" gather called AStore.FindCallersByName('TSelfOnly') with NO
  self-ref screen and added every hit's owning unit to UnitSet -- so EVERY class
  with an implemented method acquired a spurious "Used in units: <own unit>" fact,
  purely from its own method headers, and got wrongly "documented" under the
  facts-only gate. FindCallersByName itself is NOT touched (it is shared by
  rename/refactor, dead-code lint, the context bundler, and LSP/MCP references,
  which structurally need it to keep matching self-refs) -- the fix is a LOCAL
  post-filter (RefIsOwnMemberSelfRef) applied only in the Used-in-units gather.

  Two fixtures:

  Scenario 1 -- self-only class (uSelfOnlyUsedIn.pas):
    TSelfOnly has ONE implemented method, Add, and NOTHING else in the codebase
    ever references TSelfOnly. Its own qualified impl header
    'procedure TSelfOnly.Add;' is the ONLY ref to the name 'TSelfOnly' anywhere.
    After `document --qname ...TSelfOnly --apply --no-backup`, TSelfOnly must get
    NO managed block at all: no "Used in units:" line, and no reference line
    under EITHER label -- "Called from:" or, since v(ADP3 T4) relabelled a
    non-callable's references, "Used by:" -- proving the self-ref is excluded
    from BOTH facts (Called-from was already fixed by Bug C; this test's
    target is Used-in-units).

  Scenario 2 -- positive case, proves no over-exclusion (two units):
    uSharedType.pas declares TShared (one implemented method, Ping -- its own
    qualified header 'procedure TShared.Ping;' is a self-reference, same shape
    as Scenario 1). uConsumerType.pas is a SEPARATE unit that genuinely uses
    TShared twice:
      - a unit-scope 'var GShared: TShared;' in the implementation section,
        OUTSIDE any routine body (enclosing_symbol_id = NULL) -- the CRITICAL
        Bug-C-carried regression case: a NULL-enclosing ref is NOT a
        self-reference and must be KEPT, not dropped as collateral damage by
        an over-broad filter.
      - an ordinary local var 'X: TShared;' inside procedure ConsumeShared
        (enclosing routine has no parent type -- ConsumeShared is a free
        routine, not a TShared member) -- an ordinary external reference.
    After `document --qname uSharedType.TShared --apply --no-backup`, TShared
    MUST get a managed block whose "Used in units:" line names uConsumerType
    (the genuine external use is kept) and must NOT name uSharedType (TShared's
    own declaring unit -- the only ref there is the Ping self-reference, which
    must be excluded).

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-doc-no-self-usedin); each scenario
  gets its own fresh fixture dir + a TEMP db (never a real corpus db).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc-no-self-usedin"
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
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# Walk upward from a class decl line collecting the contiguous '///' block
# directly above it (same scan-upward idiom run_doc_no_self_caller.ps1 uses).
function Get-DocBlockAbove([string[]]$Lines, [string]$Pattern) {
  $idx = -1
  for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match $Pattern) { $idx = $i; break } }
  if ($idx -lt 1) { return '' }
  $blockLines = New-Object System.Collections.Generic.List[string]
  for ($i = $idx - 1; $i -ge 0; $i--) {
    if ($Lines[$i] -notmatch '^\s*///') { break }
    $blockLines.Insert(0, $Lines[$i])
  }
  return [string]::Join("`n", $blockLines.ToArray())
}

Write-Host 'Scenario 1: self-only class -- no external refs anywhere' -ForegroundColor Cyan
$dir1  = Join-Path $WorkDir 's1'
New-Item -ItemType Directory $dir1 | Out-Null
$file1 = Join-Path $dir1 'uSelfOnlyUsedIn.pas'
$db1   = Join-Path $dir1 'fx.sqlite'
Write-Ascii $file1 @'
unit uSelfOnlyUsedIn;
interface
type
  TSelfOnly = class
  public
    procedure Add;
  end;
implementation
procedure TSelfOnly.Add;
begin
end;
end.
'@
& $Exe index $dir1 --db $db1 2>&1 | Out-Null
& $Exe document --qname uSelfOnlyUsedIn.TSelfOnly --db $db1 --apply --no-backup 2>&1 | Out-Null
$ec1 = $LASTEXITCODE
Check 'document --qname exit 0' ($ec1 -eq 0) "ec=$ec1"

$lines1 = [IO.File]::ReadAllLines($file1)
$block1 = Get-DocBlockAbove $lines1 'TSelfOnly\s*=\s*class'
Check 'TSelfOnly: NO managed block at all (self-only, no genuine facts)' `
  (-not ($block1 -match [regex]::Escape('<!-- drag-lint:auto BEGIN -->'))) $block1
Check 'TSelfOnly: no "Used in units:" line' (-not ($block1 -match 'Used in units:')) $block1
# v(ADP3 T4 review round 1): anchored on EITHER label. TSelfOnly is a CLASS, so
# post-T4 CanBeCallTarget is False for it and the engine can NEVER emit
# "Called from:" here -- the check as written could not fail, and it stayed
# green BECAUSE it had gone vacuous. Widened to the same pattern
# tests/callresolve/run_callsite_kind_universe.ps1 applied to its
# CalledFromLine helper for the identical reason, and renamed to say what it
# now asserts: no reference line at all, under any label. (No coverage was lost
# while it was vacuous -- the sibling above, no managed block whatsoever, is
# strictly stronger -- but the guarantee its NAME advertised was.)
Check 'TSelfOnly: no reference line under EITHER label ("Called from:" / "Used by:")' `
  (-not ($block1 -match '(Called from:|Used by:)')) $block1

Write-Host ''
Write-Host 'Scenario 2: class used from ANOTHER unit + a unit-scope var (positive case)' -ForegroundColor Cyan
$dir2  = Join-Path $WorkDir 's2'
New-Item -ItemType Directory $dir2 | Out-Null
$fileShared   = Join-Path $dir2 'uSharedType.pas'
$fileConsumer = Join-Path $dir2 'uConsumerType.pas'
$db2 = Join-Path $dir2 'fx.sqlite'
Write-Ascii $fileShared @'
unit uSharedType;
interface
type
  TShared = class
  public
    procedure Ping;
  end;
implementation
procedure TShared.Ping;
begin
end;
end.
'@
Write-Ascii $fileConsumer @'
unit uConsumerType;
interface
uses
  uSharedType;
procedure ConsumeShared;
implementation
var
  GShared: TShared;
procedure ConsumeShared;
var
  X: TShared;
begin
  X := TShared.Create;
  X.Ping;
end;
end.
'@
& $Exe index $dir2 --db $db2 2>&1 | Out-Null
& $Exe document --qname uSharedType.TShared --db $db2 --apply --no-backup 2>&1 | Out-Null
$ec2 = $LASTEXITCODE
Check 'document --qname exit 0' ($ec2 -eq 0) "ec=$ec2"

$lines2 = [IO.File]::ReadAllLines($fileShared)
$block2 = Get-DocBlockAbove $lines2 'TShared\s*=\s*class'
Check 'TShared: HAS a managed block (genuine external use)' `
  ($block2 -match [regex]::Escape('<!-- drag-lint:auto BEGIN -->')) $block2
Check 'TShared: "Used in units:" line present' ($block2 -match 'Used in units:') $block2
Check 'TShared: "Used in units:" names uConsumerType (genuine cross-unit use kept)' `
  ($block2 -match 'Used in units:[^\r\n]*uConsumerType') $block2
Check 'TShared: "Used in units:" does NOT name uSharedType (own unit, self-ref only, excluded)' `
  (-not ($block2 -match 'Used in units:[^\r\n]*\buSharedType\b')) $block2

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
