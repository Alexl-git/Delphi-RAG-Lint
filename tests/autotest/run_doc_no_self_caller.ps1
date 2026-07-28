<#
  run_doc_no_self_caller.ps1 -- Bug C regression: FindUnresolvedNameCallers
  (DRagLint.Storage.SQLite.pas) must NOT surface a class's OWN method-header
  self-reference as a "Called from:" caller.

  ROOT CAUSE (fixed by this test): a qualified implementation header like
  'procedure TThing.Add;' emits a type_use ref of name_text='TThing' whose
  enclosing_symbol_id is the method itself (TThing.Add). Before the fix,
  FindUnresolvedNameCallers(AName='TThing') name-matched that ref and
  returned TThing.Add as a spurious caller of the CLASS TThing -- EVERY
  class with an implemented method acquired this false fact.

  Fixture (single unit, uNoSelfCaller.pas):
    - TThing: a class with ONE implemented method, Add (no params/body work,
      just 'begin end;'). Its own qualified impl header
      'procedure TThing.Add;' is the spurious self-reference source.
    - UseThing: a top-level procedure OUTSIDE TThing that declares
      'T: TThing;' and calls 'T := TThing.Create; T.Add;' -- a GENUINE
      external reference to TThing (enclosing routine UseThing has no
      parent type), proving the fix does not overreach and still keeps
      real callers.
    - GThing: a UNIT-SCOPE 'var GThing: TThing;' declared in the
      implementation section, OUTSIDE any routine body. This is the
      CRITICAL-regression case a follow-up review caught: the ref this
      line emits has enclosing_symbol_id = NULL (SQLite three-valued
      logic: 'NULL IN (...)' is NULL, and 'NOT (NULL IN (...))' is
      STILL NULL -- a WHERE predicate of NULL excludes the row, same as
      FALSE). The original Bug C fix's 'AND NOT (s.parent_id IN (...))'
      form silently dropped every such NULL-enclosing reference, not
      just self-references. The corrected form short-circuits via an
      explicit 's.parent_id IS NULL OR ...' branch so this row is KEPT.

  v(ADP3 T4) -- THE LABEL CHANGED; THE PROPERTY UNDER TEST DID NOT.
  TThing is a CLASS, and a class is never a call target, so its reference line
  is now labelled "Used by:" rather than "Called from:" (DRagLint.Doc.Regions.
  RenderFactsBlock selects the verb from TDocFacts.SymbolKind via
  DRagLint.Core.Model.CanBeCallTarget). Nothing about WHICH references reach
  that line moved -- Bug C is about the CONTENTS, and every content assertion
  below is unchanged apart from the label it anchors on. The expectation was
  updated, never the engine.

  The negative assertions are ALSO anchored on the new label, deliberately. An
  assertion of the form 'the "Called from:" line does not name X' would go
  green the moment no "Called from:" line existed at all -- which is exactly
  what T4 made true here -- and Bug C's regression guard would have silently
  stopped guarding anything while still reporting PASS.

  Asserts (after `document --qname uNoSelfCaller.TThing --apply --no-backup`,
  reading the written file):
    1. exit 0.
    2. TThing acquires a managed block (it has a genuine reference fact via
       UseThing, so facts-only does not skip it).
    3. The "Used by:" line is present and names UseThing (the real,
       external caller is KEPT).
    4. That line does NOT name TThing.Add (the class's own
       method -- a self-reference, never a meaningful caller).
    5. That line names the unit-scope GThing reference too
       (rendered as the doc engine's NULL-enclosing fallback display,
       '<TypeName> caller' -- see TDocFactsBuilder.Build.ToFactRef) --
       i.e. a legitimate reference OUTSIDE any routine is NOT dropped.
       CRITICAL: RED under the original (unfixed) WHERE clause.
    6. No "Called from:" line is emitted for the class at all (the T4 relabel,
       pinned here so a silent revert to the wrong verb is visible).

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-doc-no-self-caller); a fresh
  copy + a TEMP db (never a real corpus db).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc-no-self-caller"
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

$FixtureBody = @'
unit uNoSelfCaller;
interface
type
  TThing = class
  public
    procedure Add;
  end;
procedure UseThing;
implementation
var
  GThing: TThing;
procedure TThing.Add;
begin
end;
procedure UseThing;
var
  T: TThing;
begin
  T := TThing.Create;
  T.Add;
end;
end.
'@
function Write-Fixture([string]$Path) {
  $norm = $FixtureBody -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$dir  = Join-Path $WorkDir 'fx'
New-Item -ItemType Directory $dir | Out-Null
$file = Join-Path $dir 'uNoSelfCaller.pas'
$db   = Join-Path $dir 'fx.sqlite'
Write-Fixture $file

& $Exe index $dir --db $db 2>&1 | Out-Null
Push-Location $dir
try {
  & $Exe document --qname uNoSelfCaller.TThing --db $db --apply --no-backup 2>&1 | Out-Null
  $ec = $LASTEXITCODE
} finally {
  Pop-Location
}
Check 'document --qname exit 0' ($ec -eq 0) "ec=$ec"

$lines = [IO.File]::ReadAllLines($file)
$clsIdx = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match 'TThing\s*=\s*class') { $clsIdx = $i; break } }
Check 'TThing class decl found' ($clsIdx -ge 0)

# Walk upward from the class decl collecting the contiguous '///' block
# directly above it (same scan-upward idiom run_doc_cheap_facts.ps1 uses).
$block = ''
if ($clsIdx -ge 1) {
  $blockLines = New-Object System.Collections.Generic.List[string]
  for ($i = $clsIdx - 1; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    $blockLines.Insert(0, $lines[$i])
  }
  $block = [string]::Join("`n", $blockLines.ToArray())
}

Write-Host 'TThing class block: genuine caller kept, self-reference excluded' -ForegroundColor Cyan
Check 'TThing has a managed block (AUTO_BEGIN)' ($block -match '<!-- drag-lint:auto BEGIN -->') $block
# v(ADP3 T4): TThing is a CLASS, so its reference line reads "Used by:", not
# "Called from:". Bug C's subject -- WHICH references reach the line -- is
# untouched; only the verb moved. The two negative checks below are anchored on
# 'Used by:' for the reason the header states: anchored on the retired label
# they would pass vacuously over a line that no longer exists.
Check 'TThing has a "Used by:" line (a class is USED, not called -- v(ADP3 T4))' ($block -match 'Used by:') $block
Check 'Used by: names UseThing (real external caller kept)' ($block -match 'Used by:.*UseThing') $block
Check 'Used by: does NOT name TThing.Add (own method, self-reference excluded)' `
  (-not ($block -match 'Used by:[^\r\n]*TThing\.Add\b')) $block
Check 'Used by: includes the unit-scope GThing reference (NULL-enclosing ref kept, not dropped)' `
  ($block -match 'Used by:[^\r\n]*TThing caller\b') $block
Check 'TThing has NO "Called from:" line (v(ADP3 T4) relabel -- a class is never a call target)' `
  (-not ($block -match 'Called from:')) $block

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
