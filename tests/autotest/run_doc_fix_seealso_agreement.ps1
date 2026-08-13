<#
  run_doc_fix_seealso_agreement.ps1 -- Task 2 of
  docs\superpowers\plans\2026-08-13-shared-unit-docs-and-menu.md.

  THE INVARIANT: the doc-drift CHECKER and the doc-drift REPAIRER must render
  the managed facts block under the SAME options. DoLintAll already says so in
  a comment beside its own call (DRagLint.CLI.pas:10042):

      "The seealso flag MUST match what `document` wrote the managed blocks
       under, or the staleness compare measures the option difference, not
       drift."

  The checker honoured it -- RunDocDrift(Store, AArgs.DocSeeAlso). The repairer
  did not. TDocLintRules.FixEditsForDocDrift called the TWO-ARGUMENT convenience
  overload of TDocumenter.BuildFor, which hardcodes AIncludeSeeAlso := False
  (DRagLint.Doc.Document.pas:129). So with seealso on (the default):

    * the checker compared the stored block against a render WITH <seealso> and
      correctly reported "managed facts block is out of date", fixable;
    * the repairer regenerated the block WITHOUT <seealso>, got something
      byte-identical to what was already on disk, returned daUnchanged, and
      emitted no edit at all.

  Net effect: a doc-drift finding that no command could repair, stable across
  any number of reindexes -- which is precisely why it read as an index problem
  for three sessions. Measured on YADF 2026-08-13:
  YADF.LineScan.TLineScanState.Reset and YADF.Groups.TGroup.Create, the last two
  findings blocking that project. After the fix YADF goes 10 -> 8 with doc-drift
  at 0 and a second pass a no-op.

  THE TEST constructs the situation deterministically rather than hoping a
  hand-written block drifts the right way: it lets `document --apply` write
  CORRECT blocks (seealso on), then strips only the <seealso> lines back out.
  That is exactly the state a block written by an older/other-flagged run is in.
  The checker must then report drift AND the repair path must clear it.

  It asserts CONVERGENCE, not a message: a doc-drift finding that survives
  fix+reindex unchanged is unrepairable by any command, and that is the defect
  regardless of which option the two paths disagree about next time.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-seealso-agreement"
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
$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
if (Test-Path $dllSrc) {
  Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
  }
}

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir | Out-Null

# A record whose members call one another, so the facts builder has real
# <seealso> crefs to emit (that is what the two paths disagreed about). Mirrors
# the shape of YADF.LineScan.TLineScanState, where this was found.
$Fixture = @'
unit SeeAlsoAgree;

interface

type
  /// <summary>Scanner state with mutually-referencing members.</summary>
  TScanner = record
  public
    Depth: Integer;
    InStr: Boolean;
    /// <summary>Clears all state; call once before scanning.</summary>
    procedure Reset;
    /// <summary>Advances one step.</summary>
    procedure Step;
    /// <summary>True while inside a string literal.</summary>
    function Peek: Boolean;
  end;

implementation

procedure TScanner.Reset;
begin
  Depth := 0;
  InStr := False;
end;

procedure TScanner.Step;
begin
  if Peek then Exit;
  Inc(Depth);
end;

function TScanner.Peek: Boolean;
begin
  Result := InStr;
end;

end.
'@
$pas = Join-Path $srcDir 'SeeAlsoAgree.pas'
[System.IO.File]::WriteAllText($pas, ($Fixture -replace "`r`n","`n" -replace "`n","`r`n"), [System.Text.Encoding]::ASCII)

$db = Join-Path $WorkDir 'agree.sqlite'
& $Exe index $srcDir --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)

# 1. Let the WRITER produce correct blocks under the default flags.
& $Exe document --unit $pas --db $db --apply --no-backup 2>&1 | Out-Null
& $Exe index $srcDir --db $db 2>&1 | Out-Null
$withSeeAlso = Get-Content $pas -Raw
Check 'writer emitted <seealso> crefs' ($withSeeAlso -match '<seealso cref=') `
  'fixture must actually exercise the option the two paths disagreed about'

# 2. Strip ONLY the <seealso> lines -- the state a block written under the other
#    flag is in. Everything else about the block stays correct.
$stripped = ($withSeeAlso -split "`r`n" | Where-Object { $_ -notmatch '<seealso cref=' }) -join "`r`n"
[System.IO.File]::WriteAllText($pas, $stripped, [System.Text.Encoding]::ASCII)
& $Exe index $srcDir --db $db 2>&1 | Out-Null
Check 'seealso lines stripped' (-not ((Get-Content $pas -Raw) -match '<seealso cref='))

# 3. The CHECKER must see that as drift.
$lint0 = & $Exe lint-all --db $db --quiet 2>&1 | Out-String
$drift0 = ([regex]::Matches($lint0, 'doc-drift')).Count
Check 'checker reports the drift' ($drift0 -gt 0) `
  'if the checker is silent here the fixture no longer exercises the seam'

# 4. THE ASSERTION. The repairer must plan a fix for what the checker reported.
$fix = & $Exe lint-all --db $db --quiet --fix 2>&1 | Out-String
Check 'repairer plans a fix for what the checker reported' `
  ($fix -notmatch 'autofix: no fixable findings') `
  'checker said stale, repairer said nothing to do -- the two render under different options'

# 5. And it must actually converge: apply, reindex, drift gone.
& $Exe lint-all --db $db --quiet --fix --apply 2>&1 | Out-Null
& $Exe index $srcDir --db $db 2>&1 | Out-Null
$lint1 = & $Exe lint-all --db $db --quiet 2>&1 | Out-String
$drift1 = ([regex]::Matches($lint1, 'doc-drift')).Count
Check 'the repair converges: doc-drift reaches 0' ($drift1 -eq 0) `
  "was $drift0, now $drift1 -- a finding that survives fix+reindex is unrepairable by any command"

Check 'the repair restored the <seealso> crefs' ((Get-Content $pas -Raw) -match '<seealso cref=')

# 6. Idempotent: a second pass plans nothing.
$fix2 = & $Exe lint-all --db $db --quiet --fix 2>&1 | Out-String
Check 'second pass is a no-op' ($fix2 -match 'autofix: no fixable findings') $fix2

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
