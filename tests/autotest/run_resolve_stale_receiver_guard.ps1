<#
  run_resolve_stale_receiver_guard.ps1 -- a whole-DB call resolve must not
  overwrite receivers derived from source it can no longer trust.

  INBOX-whole-db-resolve-degrades-a-stale-index. ResolveCallTargets re-derives
  refs.receiver_text by reading the ref's source line OFF DISK, at the line/col
  recorded when that file was last INDEXED. For any file edited since, the two
  disagree: it reads an unrelated line at an unrelated column and writes whatever
  it finds -- usually ''. Not a failed refresh that leaves the old value alone, a
  successful write of a wrong one.

  Measured on the real index: one `index <single file>` run over a stale
  DragLint-Cli destroyed 11,008 receivers and 464 call edges. receiver_text is
  what stops a bare `Create` being attributed to every constructor in the index,
  so losing it silently restores exactly the fabrication it was added to prevent.

  The fix probes each file's on-disk mtime+sha against what the index recorded
  (TCallResolver.LinesOf) and WITHHOLDS the receiver write for a mismatch.

  THE POSITIVE CONTROL IS THE POINT OF THIS SUITE. The probe recomputes a SHA
  over the file and compares it with the indexer's stored one. If that hash basis
  were wrong in any way, EVERY file would look stale, every receiver write would
  be withheld, and receiver_text would silently stop being maintained -- a worse
  bug than the one being fixed, and one that no "the data survived" assertion
  would ever catch. So step 1 asserts a freshly indexed tree reports NOTHING
  withheld.

    step 1  fresh index          -> no "WITHHELD" line   (POSITIVE CONTROL)
    step 2  edit b.pas, index only the unrelated c.pas
                                 -> "WITHHELD" IS reported (the guard fires)
    step 3  b.Build STILL resolves afterwards             (the data survived)

  RED VERIFIED 2026-08-16: with the stale prescan neutralised, steps 1-2 still
  pass and step 3 FAILS with "0 caller(s)". So step 3 is the assertion that
  actually discriminates -- "the guard FIRES" alone does NOT, because the
  narrower receiver-level guard fires either way.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_stalercv'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$db = Join-Path $scratch 'stale.sqlite'

function Write-Ascii($p,$t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"),
    (New-Object System.Text.UTF8Encoding($false)))
}

Write-Ascii (Join-Path $scratch 'a.pas') @'
unit a;

interface

type
  TThing = class
    constructor Make(AValue: Integer);
  end;

implementation

constructor TThing.Make(AValue: Integer);
begin
end;

end.
'@

Write-Ascii (Join-Path $scratch 'b.pas') @'
unit b;

interface

uses
  a;

function Build: TThing;

implementation

function Build: TThing;
begin
  Result := TThing.Make(1);
end;

end.
'@

Push-Location C:\TEMP
try {
  # --- step 1: fresh index. Nothing may be considered stale. ---
  $r1 = & $exePath index $scratch --db $db 2>&1 | Out-String
  Check 'SANITY: both units indexed with no errors' `
        (($r1 -match 'a\.pas\s*->\s*\d+ symbols, \d+ refs, 0 errors') -and
         ($r1 -match 'b\.pas\s*->\s*\d+ symbols, \d+ refs, 0 errors')) $r1
  Check 'POSITIVE CONTROL: a FRESH index withholds NOTHING (hash basis matches the indexer)' `
        ($r1 -notmatch 'WITHHELD') $r1

  $res1 = & $exePath query find-callers --name Make --resolved --db $db 2>&1 | Out-String
  Check 'SANITY: Build resolves as a caller before the stale run' `
        ($res1 -match 'b\.Build\b') $res1

  # --- step 2: edit b.pas WITHOUT reindexing it, then index only a.pas. ---
  # Prepending lines shifts every ref in b.pas, so any re-derivation reads the
  # wrong line -- exactly the shape that destroyed 11,008 receivers.
  $bPath = Join-Path $scratch 'b.pas'
  Write-Ascii $bPath ("{ shifted }`r`n{ shifted }`r`n{ shifted }`r`n" + [System.IO.File]::ReadAllText($bPath))

  # --force-reparse is the note's own measured repro shape ("index ONE file into a
  # stale DB"), and it takes the whole-corpus resolve path, which is where the
  # full exposure lives. Without it the run reports "calls skipped -- no file
  # changed" and resolves nothing at all, so the assertion below would be
  # vacuous rather than passing.
  # Trigger the pass by indexing an UNRELATED new file, NOT a.pas.
  #
  # Indexing a.pas would re-parse the declaring unit, re-issuing TThing.Make's
  # symbol id, and b's edge would die by FK cascade -- correct behaviour, and
  # nothing to do with this defect. Using a third file keeps a.pas's ids stable
  # so the only thing that could destroy b's edge is this pass rewriting it,
  # which is exactly what is under test.
  Write-Ascii (Join-Path $scratch 'c.pas') @'
unit c;

interface

procedure Unrelated;

implementation

procedure Unrelated; begin end;

end.
'@
  $env:DRAGLINT_NO_SCOPED_RESOLVE = '1'   # force the full-corpus path deterministically
  try {
    # ONLY c.pas -- indexing the whole folder would re-index the edited b.pas,
    # making it fresh again and leaving nothing stale to guard.
    $r2 = & $exePath index (Join-Path $scratch 'c.pas') --db $db 2>&1 | Out-String
  } finally { Remove-Item Env:\DRAGLINT_NO_SCOPED_RESOLVE -ErrorAction SilentlyContinue }

  Check 'SANITY: the resolve pass actually ran (else the next assert is vacuous)' `
        ($r2 -match 'resolve: calls\s+\d+ edge') $r2
  Check 'the guard FIRES: a stale source file has its receiver write withheld' `
        ($r2 -match 'WITHHELD') $r2

  # --- step 3: the stored data survived the stale run. ---
  $res2 = & $exePath query find-callers --name Make --resolved --db $db 2>&1 | Out-String
  Check 'DATA SURVIVED: Build is STILL a resolved caller after the stale run' `
        ($res2 -match 'b\.Build\b') $res2
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
