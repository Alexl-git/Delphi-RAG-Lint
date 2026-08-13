<#
  run_autofix_apply_accounting.ps1 -- Task 1 of
  docs\superpowers\plans\2026-08-13-shared-unit-docs-and-menu.md.

  THE DEFECT, as reproduced on YADF 2026-08-13. Three consecutive
  `lint-all --project YADF.dproj --fix --apply` passes, each followed by a full
  reindex, printed the identical line:

      autofix: applied 11 fix(es) across 0 file(s), 22 skipped (stale index)

  Two defects in one line, and the plan named two candidate causes for the
  second. BOTH candidates were wrong; the measured cause is a third thing:

  1. ACCOUNTING. `applied 11` is FixCount -- the count of fixable FINDINGS --
     while `across 0 file(s)` is the count of files actually written. One
     doc-drift finding emits a delete+insert PAIR, so 11 findings produced 22
     edits, every one of which was refused. "applied 11 across 0 files" is
     self-contradictory on its face and it reported work that did not happen.

  2. SCOPE. `TDocLintRules.FixEditsForDocDrift(AStore)` took ONLY the store and
     walked every documented public decl in the whole database -- it was never
     handed the findings that triggered it. So a single doc-drift finding in
     YADF's own code made --fix plan 22 edits into C:\Projects\DelphiAST, a
     vendored third-party root that the SAME command had just reported as
     skipped ("8 file(s) outside the project's own roots skipped"), and which is
     no longer in the project's compile closure at all. Those rows are ghosts
     the indexer neither re-parses nor evicts, so their line numbers are frozen
     ~150 lines out of date (TmwSimplePasParEx.PushNames: store said 564, the
     779-line file has it at 414). AnchorIsValid then correctly refused all 22 --
     and no reindex could ever clear them, because nothing re-parses or evicts a
     ghost row. Confirmed by `index --all --only YADF --force-reparse`, which
     parses 9 files while the DB reports files=18.

     This is the same defect `document --project` was fixed for on 2026-08-12
     (docs\INBOX-document-project-ignores-ownroots-and-writes-into-third-party.md,
     severity: high -- "it modifies source outside the project under a command
     the user aimed at their own project"). The repair path never got the same
     treatment. Evidence it had already fired: DelphiAST.pas.bak and
     SimpleParser.Types.pas.bak, written 2026-08-13 10:22 into a vendored repo.

     The sibling FixEditsForMissingDoc(AStore, ATargeted) was ALREADY scoped to
     the targeted findings, two functions away in the same class. That is the
     precedent this fix copies.

  FIXTURE: the YADF/DelphiAST shape at small scale -- an owned project whose
  decls carry stale managed facts blocks, plus a vendored root indexed into the
  SAME database whose decls are stale in exactly the same way. ownRoots declares
  only the project. A correct --fix repairs the first and never touches the
  second.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-autofix-accounting"
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

# tree-sitter Win64 DLLs must sit beside the exe (mirrors _manifest_common.ps1).
$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
if (Test-Path $dllSrc) {
  Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
  }
}

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$projDir = Join-Path $WorkDir 'proj'
$venDir  = Join-Path $WorkDir 'vendor'
$dragDir = Join-Path $projDir '_D-RAG'
New-Item -ItemType Directory $projDir | Out-Null
New-Item -ItemType Directory $venDir  | Out-Null
New-Item -ItemType Directory $dragDir | Out-Null

function Write-Ascii([string]$Path, [string]$Text) {
  $norm = $Text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# THREE owned decls that all need the same fixable doc repair: each managed facts
# block claims a `Calls:` target that does not exist, while the body really calls
# Helper. ddFactsBlockStale is Fixable, so each yields a delete+insert PAIR --
# which is what makes the 11-vs-22 accounting bug observable at all.
$App = @'
unit App;

interface

/// <summary>Does the first thing.</summary>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Calls: NoSuchRoutineOne
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure AlphaOne;

/// <summary>Does the second thing.</summary>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Calls: NoSuchRoutineTwo
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure AlphaTwo;

/// <summary>Does the third thing.</summary>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Calls: NoSuchRoutineThree
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure AlphaThree;

implementation

procedure Helper;
begin
end;

procedure AlphaOne;
begin
  Helper;
end;

procedure AlphaTwo;
begin
  Helper;
end;

procedure AlphaThree;
begin
  Helper;
end;

end.
'@

# The vendored unit: same stale shape, OUTSIDE ownRoots, indexed into the SAME db.
# This is DelphiAST's role in the real defect.
$Vendor = @'
unit Vendor;

interface

/// <summary>A vendored routine nobody here owns.</summary>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Calls: NoSuchVendorRoutine
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure VendorOne;

implementation

procedure VendorHelper;
begin
end;

procedure VendorOne;
begin
  VendorHelper;
end;

end.
'@

$appPas = Join-Path $projDir 'App.pas'
$venPas = Join-Path $venDir  'Vendor.pas'
Write-Ascii $appPas $App
Write-Ascii $venPas $Vendor
Write-Ascii (Join-Path $projDir 'App.dproj') '<Project/>'
Write-Ascii (Join-Path $dragDir 'drag-lint-project.json') '{ "ownRoots": ["."] }'

# One database holding BOTH roots -- exactly how DelphiAST ended up inside
# YADF.sqlite. The db lives in _D-RAG so the ownRoots anchor resolves.
$db = Join-Path $dragDir 'App.sqlite'
& $Exe index $projDir --db $db 2>&1 | Out-Null
& $Exe index $venDir  --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)

$rep = Join-Path $WorkDir 'report.txt'
$venHashBefore = (Get-FileHash $venPas -Algorithm SHA256).Hash

# ---------------------------------------------------------------- dry run ----
$dry = & $Exe lint-all --db $db --output $rep --fix 2>&1 | Out-String

Check 'lint-all sees the owned drift' ($dry -match 'autofix: \d+ fixable finding') $dry

# THE ROOT-CAUSE ASSERTION. The repair planner must be scoped to the findings it
# was given, which the ownership filter has already narrowed to the project.
Check 'no planned edit targets the vendored root' (-not ($dry -match 'Vendor\.pas')) `
  'a command that reports a root as skipped must not offer to write into it'
Check 'the owned unit IS planned for repair' ($dry -match 'App\.pas') $dry

# ------------------------------------------------------------------ apply ----
$applyOut = & $Exe lint-all --db $db --output $rep --fix --apply 2>&1 | Out-String

$applied = -1; $touched = -1; $skipped = 0
# Accept the pre-fix wording ("fix(es)") and the post-fix wording ("edit(s)") so
# this test fails on SEMANTICS, never on a rename of the noun.
if ($applyOut -match 'autofix: applied (\d+) (?:fix\(es\)|edit\(s\)) across (\d+) file\(s\)(?:, (\d+) skipped)?') {
  $applied = [int]$Matches[1]
  $touched = [int]$Matches[2]
  $skipped = if ($Matches[3]) { [int]$Matches[3] } else { 0 }
}
Check 'apply printed a parsable summary' ($applied -ge 0) $applyOut

Check 'applied is 0 when no file was touched' (-not (($touched -eq 0) -and ($applied -gt 0))) `
  'reporting work that was not done is worse than reporting none'

# The accounting invariant stated positively, so it is checkable on a run where
# nothing is refused: the summary must count EDITS, and the dry run above listed
# exactly the edits that were about to be written.
$plannedEdits = ([regex]::Matches($dry, '(?m)^  (?:delete lines|insert after line|insert at L|replace L)')).Count
Check 'apply counts EDITS WRITTEN, not fixable findings' ($applied -eq $plannedEdits) `
  "summary said $applied, the plan held $plannedEdits edit(s)"
Check 'first pass skipped nothing' ($skipped -eq 0) $applyOut
Check 'first pass wrote the owned file' ($touched -ge 1) $applyOut

# The safety assertion the .bak files in C:\Projects\DelphiAST prove we needed.
Check 'the vendored file is byte-identical after --apply' `
  ((Get-FileHash $venPas -Algorithm SHA256).Hash -eq $venHashBefore) `
  'autofix must never write outside the project it was aimed at'
Check 'no .bak was written into the vendored root' `
  (-not (Test-Path (Join-Path $venDir 'Vendor.pas.bak')))

Check 'the stale fact is gone from the owned file' `
  (-not ((Get-Content $appPas -Raw) -match 'NoSuchRoutineOne')) `
  'the repair must actually repair'

# ------------------------------------------------------------ second pass ----
# Reindex so the store matches what was just written, then re-run. A repair path
# that has converged plans nothing and skips nothing.
& $Exe index $projDir --db $db 2>&1 | Out-Null
$second = & $Exe lint-all --db $db --output $rep --fix --apply 2>&1 | Out-String

$secondSkipped = 0
if ($second -match 'autofix: applied \d+ (?:fix\(es\)|edit\(s\)) across \d+ file\(s\)(?:, (\d+) skipped)?') {
  $secondSkipped = if ($Matches[1]) { [int]$Matches[1] } else { 0 }
}
Check 'second pass converges: nothing left to skip' ($secondSkipped -eq 0) `
  'a skip that survives a reindex is unrepairable by any command'
Check 'second pass is idempotent: no fixable findings left' `
  ($second -match 'autofix: no fixable findings') $second

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
