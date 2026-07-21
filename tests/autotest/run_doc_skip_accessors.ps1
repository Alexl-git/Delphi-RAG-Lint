<#
  run_doc_skip_accessors.ps1 -- Whole-Project Auto-Document Phase 1 / Task 2:
  batch document modes (--unit/--project/document-all) skip TRIVIAL Get*/Set*
  property accessors so they do not clutter a unit with one-line getter/setter
  doc comments; --include-accessors opts back in; document --qname is never
  filtered.

  ACCESSOR-DETECTION APPROACH (see the task report for the full rationale):
  the index has NO stored method<->property linkage (a property symbol's
  prop_access column is its ro/rw/wo MODE, not the accessor method's id), so
  the filter is a deliberate fallback heuristic: a class method (Kind=skMethod)
  named Get*/Set* whose recorded impl body span (ImplEndLine - ImplStartLine)
  is <= accessor_trivial_max_lines (default 2, from docs.accessor_trivial_max_lines)
  is treated as trivial and skipped in batch modes.

  Fixture (uAccessorSkip.pas): TThing has
    - FA/FB fields (private).
    - GetA / SetA: the property A accessors, each written as ONE physical
      source line ('function TThing.GetA: Integer; begin Result := FA; end;')
      so ImplStartLine = ImplEndLine (diff 0 <= 2) -- TRIVIAL.
    - GetB: the property B accessor, written across several lines (header,
      var, begin, 2 statements, end) so its impl body diff is > 2 --
      NOT trivial (it does "real work": LTemp := FB * 2; Result := LTemp + 1).
    - DoWork: an ordinary procedure (not Get*/Set*-named), calling
      GetA/SetA/GetB so all three accessors + DoWork carry real
      Called-from/Calls facts (managed AUTO_BEGIN block) -- proving any
      skip/keep decision below is the ACCESSOR filter, not the pre-existing
      facts-only gate coincidentally dropping them for lack of facts.
    - property A/B are never documented themselves (skProperty is not in
      TDocBatch's documentable-kind list; unaffected either way).
    - All doc-comment insertions land above the INTERFACE (class-body)
      declaration line, never above the qualified implementation header --
      verified against the actual engine output before this test was
      finalized (see the task report). Test-DocAbove below matches the
      bare interface-section signature only.

  NOTE (UPDATED post-Bug-C/Bug-D; was a pre-existing quirk when this test was
  written): TThing (the class) itself does NOT pick up a facts block in any
  scenario below. It USED TO -- each qualified impl header (e.g. 'function
  TThing.GetA: Integer;') emits a type_use reference to 'TThing', and that
  self-reference was, at the time, surfaced unfiltered as BOTH an "unverified
  caller" via FindUnresolvedNameCallers ("Called from:") and a "using unit"
  via FindCallersByName ("Used in units: uAccessorSkip", TThing's own
  declaring unit) -- so every implemented method's own header qualifier made
  the class look both called-from and used-in-its-own-unit, and facts-only
  kept it. Both leaks are now fixed as LOCAL fixes, not touching either shared
  store method: Called-from screens self-refs in the "Called from" gather
  (DRagLint.Doc.Facts.pas, fixed alongside FindUnresolvedNameCallers's own
  NULL-safe SQL fix); Used-in-units screens them via the local
  RefIsOwnMemberSelfRef helper in the "Used in units" gather. TThing in this
  fixture has NO other reference anywhere (no external caller, no other
  unit uses it), so it now correctly has ZERO facts and is NOT documented --
  DocCount below is 2 (GetB + DoWork) in scenario 1b and 4 (GetA + SetA +
  GetB + DoWork) in scenario 3b, one less than DeclCount in each case. This
  test still asserts only DeclCount/AccessorsSkipped/the per-accessor
  skip-vs-keep decisions as its actual ADP1 T2 contract -- it does
  NOT assert anything about TThing's own comment content.

  Asserts:
    1. `document --unit <file> --apply` (default, no --include-accessors):
       documents GetB + DoWork, does NOT document GetA/SetA. --json on a
       fresh copy: declCount=3 (TThing class + GetB + DoWork; GetA/SetA are
       excluded BEFORE DeclCount, like a private/non-documentable decl),
       docCount=2 (GetB + DoWork only -- TThing has no facts, see the NOTE
       above), accessorsSkipped=2. Plain-text output reports "2 trivial
       accessor(s) skipped".
    2. `document --qname <...TThing.GetA>` (single-symbol path) DOES
       document GetA -- proves the accessor filter is batch-mode-only.
    3. `document --unit <file> --include-accessors --apply` documents all
       four (GetA, SetA, GetB, DoWork). --json: declCount=5, docCount=4
       (GetA + SetA + GetB + DoWork -- TThing has no facts, see the NOTE
       above; --include-accessors only disables the ADP1 T2 filter, not the
       facts-only gate), accessorsSkipped=0.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-doc-skip-accessors); each
  scenario gets its own fresh copy + temp DB (never a real corpus DB).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc-skip-accessors"
)
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
# Resolve $Exe to an ABSOLUTE path up front (mirrors run_doc_returns_and_callers.ps1):
# scenarios below do not Push-Location, but keep the discipline for safety.
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$FixtureBody = @'
unit uAccessorSkip;

interface

type
  TThing = class
  private
    FA: Integer;
    FB: Integer;
    function GetA: Integer;
    procedure SetA(Value: Integer);
    function GetB: Integer;
  public
    property A: Integer read GetA write SetA;
    property B: Integer read GetB;
    procedure DoWork;
  end;

implementation

function TThing.GetA: Integer; begin Result := FA; end;
procedure TThing.SetA(Value: Integer); begin FA := Value; end;

function TThing.GetB: Integer;
var
  LTemp: Integer;
begin
  LTemp := FB * 2;
  Result := LTemp + 1;
end;

procedure TThing.DoWork;
var
  LVal: Integer;
begin
  LVal := GetA();
  SetA(LVal + 1);
  FB := GetB();
end;

end.
'@
function Write-Fixture([string]$Path) {
  $norm = $FixtureBody -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# Line-above-decl helper: True when the line immediately above the first line
# matching $Pattern starts a '///' doc comment (scans upward through a
# multi-line /// block, same idiom run_document_unit.ps1 uses for a single
# line, extended to tolerate a multi-line comment directly above).
function Test-DocAbove([string[]]$Lines, [string]$Pattern) {
  $idx = -1
  for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match $Pattern) { $idx = $i; break } }
  if ($idx -le 0) { return $false }
  return ($Lines[$idx - 1] -match '^\s*///')
}

Write-Host 'Scenario 1: default batch (document --unit, no --include-accessors)' -ForegroundColor Cyan
$dir1  = Join-Path $WorkDir 's1'
New-Item -ItemType Directory $dir1 | Out-Null
$file1 = Join-Path $dir1 'uAccessorSkip.pas'
$db1   = Join-Path $dir1 'fx.sqlite'
Write-Fixture $file1
& $Exe index $dir1 --db $db1 2>&1 | Out-Null
$out1 = & $Exe document --unit $file1 --db $db1 --apply --no-backup 2>$null | Out-String
$ec1 = $LASTEXITCODE
Check 'exit 0' ($ec1 -eq 0) "ec=$ec1"

$lines1 = [IO.File]::ReadAllLines($file1)
Check 'GetB documented (/// above its interface decl)'    (Test-DocAbove $lines1 '^\s*function GetB: Integer;\s*$')
Check 'DoWork documented (/// above its interface decl)'  (Test-DocAbove $lines1 '^\s*procedure DoWork;\s*$')
Check 'GetA NOT documented (trivial accessor, one-line)' (-not (Test-DocAbove $lines1 '^\s*function GetA: Integer;\s*$'))
Check 'SetA NOT documented (trivial accessor, one-line)' (-not (Test-DocAbove $lines1 '^\s*procedure SetA\(Value: Integer\);\s*$'))
Check 'summary reports "2 trivial accessor(s) skipped"' ($out1 -match '2 trivial accessor\(s\) skipped') $out1

Write-Host ''
Write-Host 'Scenario 1b: same default batch, --json exact counts (fresh copy)' -ForegroundColor Cyan
$dir1b  = Join-Path $WorkDir 's1b'
New-Item -ItemType Directory $dir1b | Out-Null
$file1b = Join-Path $dir1b 'uAccessorSkip.pas'
$db1b   = Join-Path $dir1b 'fx.sqlite'
Write-Fixture $file1b
& $Exe index $dir1b --db $db1b 2>&1 | Out-Null
$rj1b = & $Exe document --unit $file1b --db $db1b --json 2>$null | Out-String
$ecj1b = $LASTEXITCODE
$oj1b = $null; try { $oj1b = ($rj1b | ConvertFrom-Json) } catch { $oj1b = $null }
Check 'json: exit 0' ($ecj1b -eq 0)
Check 'json: declCount = 3 (TThing + GetB + DoWork; GetA/SetA excluded pre-count)' `
  ($null -ne $oj1b -and [int]$oj1b.declCount -eq 3) "declCount=$($oj1b.declCount)"
Check 'json: docCount = 2 (GetB + DoWork; TThing has no facts, see the NOTE above)' `
  ($null -ne $oj1b -and [int]$oj1b.docCount -eq 2) "docCount=$($oj1b.docCount)"
Check 'json: accessorsSkipped = 2 (GetA + SetA)' `
  ($null -ne $oj1b -and [int]$oj1b.accessorsSkipped -eq 2) "accessorsSkipped=$($oj1b.accessorsSkipped)"

Write-Host ''
Write-Host 'Scenario 2: document --qname on the trivial accessor (single-symbol path never filtered)' -ForegroundColor Cyan
$dir2  = Join-Path $WorkDir 's2'
New-Item -ItemType Directory $dir2 | Out-Null
$file2 = Join-Path $dir2 'uAccessorSkip.pas'
$db2   = Join-Path $dir2 'fx.sqlite'
Write-Fixture $file2
& $Exe index $dir2 --db $db2 2>&1 | Out-Null
& $Exe document --qname uAccessorSkip.TThing.GetA --db $db2 --apply --no-backup 2>&1 | Out-Null
$ec2 = $LASTEXITCODE
Check 'exit 0' ($ec2 -eq 0) "ec=$ec2"
$lines2 = [IO.File]::ReadAllLines($file2)
Check 'GetA IS documented via --qname (bypasses the batch accessor filter)' `
  (Test-DocAbove $lines2 '^\s*function GetA: Integer;\s*$')

Write-Host ''
Write-Host 'Scenario 3: document --unit --include-accessors (opt back in)' -ForegroundColor Cyan
$dir3  = Join-Path $WorkDir 's3'
New-Item -ItemType Directory $dir3 | Out-Null
$file3 = Join-Path $dir3 'uAccessorSkip.pas'
$db3   = Join-Path $dir3 'fx.sqlite'
Write-Fixture $file3
& $Exe index $dir3 --db $db3 2>&1 | Out-Null
& $Exe document --unit $file3 --db $db3 --include-accessors --apply --no-backup 2>&1 | Out-Null
$ec3 = $LASTEXITCODE
Check 'exit 0' ($ec3 -eq 0) "ec=$ec3"
$lines3 = [IO.File]::ReadAllLines($file3)
Check 'GetA documented'   (Test-DocAbove $lines3 '^\s*function GetA: Integer;\s*$')
Check 'SetA documented'   (Test-DocAbove $lines3 '^\s*procedure SetA\(Value: Integer\);\s*$')
Check 'GetB documented'   (Test-DocAbove $lines3 '^\s*function GetB: Integer;\s*$')
Check 'DoWork documented' (Test-DocAbove $lines3 '^\s*procedure DoWork;\s*$')

Write-Host ''
Write-Host 'Scenario 3b: same --include-accessors run, --json exact counts (fresh copy)' -ForegroundColor Cyan
$dir3b  = Join-Path $WorkDir 's3b'
New-Item -ItemType Directory $dir3b | Out-Null
$file3b = Join-Path $dir3b 'uAccessorSkip.pas'
$db3b   = Join-Path $dir3b 'fx.sqlite'
Write-Fixture $file3b
& $Exe index $dir3b --db $db3b 2>&1 | Out-Null
$rj3b = & $Exe document --unit $file3b --db $db3b --include-accessors --json 2>$null | Out-String
$ecj3b = $LASTEXITCODE
$oj3b = $null; try { $oj3b = ($rj3b | ConvertFrom-Json) } catch { $oj3b = $null }
Check 'json: exit 0' ($ecj3b -eq 0)
Check 'json: declCount = 5 (TThing + GetA + SetA + GetB + DoWork)' `
  ($null -ne $oj3b -and [int]$oj3b.declCount -eq 5) "declCount=$($oj3b.declCount)"
Check 'json: docCount = 4 (GetA + SetA + GetB + DoWork; TThing has no facts, see the NOTE above)' `
  ($null -ne $oj3b -and [int]$oj3b.docCount -eq 4) "docCount=$($oj3b.docCount)"
Check 'json: accessorsSkipped = 0 (filter disabled for this run)' `
  ($null -ne $oj3b -and [int]$oj3b.accessorsSkipped -eq 0) "accessorsSkipped=$($oj3b.accessorsSkipped)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
