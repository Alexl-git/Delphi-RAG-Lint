<#
  run_doc_orphan_block.ps1 -- `doc-orphan-block`: a managed facts block attached
  to NO declaration.

  WHY THIS RULE EXISTS, and why it is not part of doc-drift. doc-drift walks
  SYMBOLS and asks whether each one's block is current. An orphan block belongs
  to no symbol -- that is what makes it an orphan -- so it is invisible to
  doc-drift by construction, and equally invisible to every convergence gate
  built on doc-drift.

  That is not theoretical. Measured 2026-08-14 on YADF at b65b2f9, the commit
  whose own message says autodoc CONVERGES:

      document --project {YADF,YADFOT,YADFSetup}  ->  "nothing to document" x3
      YADF.Options.pas lines 486/499              ->  a stacked orphan pair

  Both statements were true at once. The gate reported done over corrupted
  source, because the documenter neither rewrites nor removes what it cannot
  associate with a declaration, and truthfully says it has no work. A wide apply
  the same day added two more pairs and the gate stayed green through all of it.

  THE PREDICATE: between two consecutive `drag-lint:auto BEGIN` markers there
  must be at least one line of CODE. One declaration gets one managed block, so
  two blocks with nothing declared between them means the FIRST is unreachable.

  Deliberately conservative -- see the rule's own comment in
  DRagLint.Diagnostics.DeadCodeChecks. False negatives (a braced comment's
  interior lines read as code) are preferred to false positives, because a rule
  that cries wolf about ordinary comments gets switched off. Measured on
  drag-lint's own source, the largest managed-block corpus available: 0 findings.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

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

$W = Join-Path $env:TEMP 'drag-lint-orphan-block'
if (Test-Path $W) { Remove-Item -Recurse -Force -LiteralPath $W }
New-Item -ItemType Directory $W | Out-Null

function Write-Ascii([string]$Path, [string]$Text) {
  $n = $Text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $n, [System.Text.Encoding]::ASCII)
}
function OrphanFindings([string]$File) {
  @(& $Exe lint $File 2>$null | Select-String '\] doc-orphan-block:')
}

# --- THE DEFECT: two blocks, two blank lines, one declaration -----------------
# Byte-for-byte the shape found in YADF.Options.pas.
Write-Ascii "$W\Stacked.pas" @'
unit Stacked;

interface

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: Other.Thing (Other.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>


  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: Other.Thing (Other.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TStacked = record
    Value: Integer;
  end;

implementation

end.
'@

# --- CONTROL: the SAME two blocks, each with its own declaration --------------
# This is the ordinary shape of a documented interface section and MUST be
# silent. Without it the rule could "pass" by flagging every second block.
Write-Ascii "$W\Normal.pas" @'
unit Normal;

interface

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: Other.Thing (Other.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TFirst = record
    Value: Integer;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: Other.Thing (Other.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSecond = record
    Value: Integer;
  end;

implementation

end.
'@

# --- CONTROL: a single block. One BEGIN can never be an orphan pair. ----------
Write-Ascii "$W\Single.pas" @'
unit Single;

interface

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: Other.Thing (Other.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSingle = record
    Value: Integer;
  end;

implementation

end.
'@

# --- THE DEFECT AGAIN, with DIFFERING content --------------------------------
# The case the 2026-08-13 duplicate-insert guard (a233d1d) explicitly does NOT
# cover: when regenerated text differs there is no duplicate to recognise, so
# that guard cannot be what catches this. Observed at YADF.Options.pas 494/507.
Write-Ascii "$W\StackedDiff.pas" @'
unit StackedDiff;

interface

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: Other.Thing (Other.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>


  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: Other.Thing (Other.pas), Third.Thing (Third.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TStackedDiff = record
    Value: Integer;
  end;

implementation

end.
'@

Write-Host 'doc-orphan-block' -ForegroundColor Cyan

$st = OrphanFindings "$W\Stacked.pas"
Check 'a stacked pair is reported' ($st.Count -eq 1) "got $($st.Count)"
# Anchored on the FIRST block's BEGIN MARKER (line 7), not on the `<remarks>`
# opener above it (line 6). The marker is the unambiguous thing -- it is what the
# predicate actually matched, and what the message names. A reader deleting the
# block still needs the line above; the message gives both bounds rather than
# making the anchor guess at a region start it never computed.
Check 'it anchors on the FIRST block -- the one to delete' `
  ($st.Count -eq 1 -and $st[0].Line -match 'Stacked\.pas:7:') `
  $(if ($st.Count) { $st[0].Line.Trim() } else { '(no finding)' })

$sd = OrphanFindings "$W\StackedDiff.pas"
Check 'a stacked pair with DIFFERING content is reported' ($sd.Count -eq 1) `
  'the case the duplicate-insert guard cannot see'

$nm = OrphanFindings "$W\Normal.pas"
Check 'two blocks with their own declarations are silent' ($nm.Count -eq 0) `
  "got $($nm.Count) -- this control is what stops the rule flagging every second block"

$sg = OrphanFindings "$W\Single.pas"
Check 'a single block is silent' ($sg.Count -eq 0) "got $($sg.Count)"

Write-Host ''
if ($script:Failed) { Write-Host 'run_doc_orphan_block: FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'run_doc_orphan_block: OK' -ForegroundColor Green
exit 0
