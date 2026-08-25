<#
  run_docdrift_fix_removal.ps1 -- `--fix --apply` must repair a doc-drift finding
  whose correct repair is a DELETION, not only one that is a rewrite.

  THE DEFECT THIS PINS (fixed 2026-08-25). FinalizeAndOutput counted one fix per
  repaired span by counting tekInsertLines edits, on the stated premise that
  "BuildFor emits a delete+insert PAIR per span". That holds for a REWRITE and
  fails for a REMOVAL: when the fresh render has no facts at all, BuildFor emits
  a DELETE ALONE. Zero inserts left FixCount at 0 -- and the apply is gated on
  `FixCount > 0`, so the edit was built, added to the edit list, and then never
  written, while the summary said

      autofix: no fixable findings (of 2 finding(s))

  which is false in both halves: the finding IS fixable and a repair HAD been
  produced. Under DRAGLINT_FIXDOC_TRACE the same run printed
  `FIXDOC OK 1 edit(s)` next to an untouched file, which is what finally located
  it. Silent, and it looks exactly like "the fixer does not support this rule".

  THE TWO SHAPES MUST BE IN SEPARATE RUNS, AND THAT IS THE WHOLE TRICK.
  The first version of this suite put both in ONE lint-all run and PASSED against
  the unfixed build -- worthless as a guard. The rewrite's insert pushed FixCount
  to 1, which opened the `FixCount > 0` apply gate, and the removal edit was
  already in the same Edits array and got written as a passenger. The bug only
  bites when EVERY repair in a run is a removal. So each shape gets its own index
  and its own run:

    uLone.pas   TLone.Solo   -- public, NOBODY calls it, empty body. The fresh
                                render is EMPTY, so the repair is `delete lines
                                N..M` with no insert. This is the case that was
                                broken.
    uPair.pas   TPair.Ping   -- called by Drive in the same unit, so the fresh
                                render is NON-empty and the repair is the
                                ordinary delete+insert PAIR.

  The rewrite case is the regression guard on the fix itself: the new count is
  (inserts + unpaired deletes), so a bug there would either stop counting
  rewrites or start double-counting them. Asserting only the removal would let a
  "count every edit" change pass while inflating every rewrite to 2.

  Both blocks are hand-written to name a caller that cannot exist, so both are
  genuinely stale and neither depends on cross-DB behaviour.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_ddfix_removal'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Ascii($p,$t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"),
    (New-Object System.Text.UTF8Encoding($false)))
}

New-Item -ItemType Directory -Path (Join-Path $scratch 'lone') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $scratch 'pair') | Out-Null

# --- REMOVAL case: no caller, empty body -> the fresh render has no facts -----
# ALONE in its own index, so this run's ONLY repair is a deletion.
Write-Ascii (Join-Path $scratch 'lone\uLone.pas') @'
unit uLone;

interface

type
  TLone = class
  public
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: Nobody.Nowhere (nowhere.pas)</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure Solo;
  end;

implementation

procedure TLone.Solo;
begin
end;

end.
'@

# --- REWRITE case: a real caller, so the render is non-empty ------------------
Write-Ascii (Join-Path $scratch 'pair\uPair.pas') @'
unit uPair;

interface

type
  TPair = class
  public
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: Nobody.Nowhere (nowhere.pas)</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure Ping;
  end;

procedure Drive;

implementation

procedure TPair.Ping;
begin
end;

procedure Drive;
var
  P: TPair;
begin
  P := TPair.Create;
  P.Ping;
  P.Free;
end;

end.
'@

$loneDir = Join-Path $scratch 'lone'
$pairDir = Join-Path $scratch 'pair'
$lone    = Join-Path $loneDir 'uLone.pas'
$pair    = Join-Path $pairDir 'uPair.pas'
$loneDb  = Join-Path $scratch 'lone.sqlite'
$pairDb  = Join-Path $scratch 'pair.sqlite'

Push-Location C:\TEMP
try {
  & $exePath index $loneDir --db $loneDb 2>&1 | Out-Null
  & $exePath index $pairDir --db $pairDb 2>&1 | Out-Null

  # SANITY: each block is genuinely reported as drifted before any fix. Without
  # this, everything below is satisfied by an engine that reports nothing.
  $repL = (& $exePath lint-all --db $loneDb --quiet 2>&1 | Out-String)
  $repP = (& $exePath lint-all --db $pairDb --quiet 2>&1 | Out-String)
  Check 'SANITY: the removal-case block is reported as doc-drift' ($repL -match 'doc-drift') $repL
  Check 'SANITY: the rewrite-case block is reported as doc-drift' ($repP -match 'doc-drift') $repP

  # === THE DEFECT: a run whose ONLY repair is a DELETION ===================
  $outL = (& $exePath lint-all --db $loneDb --fix --apply 2>&1 | Out-String)
  Check 'REMOVAL run does NOT report "no fixable findings"' `
        ($outL -notmatch 'no fixable findings') `
        (($outL -split "`r?`n" | Where-Object { $_ -match 'autofix' }) -join ' / ')
  Check 'REMOVAL run reports edits APPLIED' `
        ($outL -match 'autofix: applied \d+ edit') `
        (($outL -split "`r?`n" | Where-Object { $_ -match 'autofix' }) -join ' / ')
  Check 'REMOVAL: the unaccountable block is actually deleted from the file' `
        (-not ((Get-Content $lone -Raw) -match 'Nobody\.Nowhere')) `
        (Get-Content $lone -Raw)

  # === REGRESSION GUARD on the fix itself: the ordinary rewrite still works =
  # The new count is (inserts + unpaired deletes). A bug there would either stop
  # counting rewrites or double-count them, and this is what would notice.
  $outP = (& $exePath lint-all --db $pairDb --fix --apply 2>&1 | Out-String)
  Check 'REWRITE run still applies its repair' `
        ($outP -match 'autofix: applied \d+ edit') `
        (($outP -split "`r?`n" | Where-Object { $_ -match 'autofix' }) -join ' / ')
  $pairTxt = (Get-Content $pair -Raw)
  Check 'REWRITE: the stale caller is replaced by the real one' `
        (($pairTxt -notmatch 'Nobody\.Nowhere') -and ($pairTxt -match 'uPair\.Drive')) `
        $pairTxt

  # === CONVERGENCE =========================================================
  # Reindex first: doc-drift's population comes from ListDocumentedSymbols, i.e.
  # the INDEX, and the source has just changed under it. A repair that merely
  # swapped one stale block for another would surface here as drift that never
  # clears.
  & $exePath index $loneDir --db $loneDb 2>&1 | Out-Null
  & $exePath index $pairDir --db $pairDb 2>&1 | Out-Null
  $afterL = (& $exePath lint-all --db $loneDb --quiet 2>&1 | Out-String)
  $afterP = (& $exePath lint-all --db $pairDb --quiet 2>&1 | Out-String)
  Check 'CONVERGENCE: no doc-drift remains in either file after reindex' `
        (($afterL -notmatch 'doc-drift') -and ($afterP -notmatch 'doc-drift')) `
        ((($afterL + $afterP) -split "`r?`n" | Where-Object { $_ -match 'doc-drift' }) -join ' / ')
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
