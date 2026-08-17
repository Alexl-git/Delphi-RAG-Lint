<#
  run_index_calls_resolve_announce.ps1 -- the call-target resolve says WHICH
  shape it is about to run, and WHY, BEFORE it runs.

  INBOX-incremental-index-hangs-on-large-db, reproduced 2026-08-17. Indexing 84
  new files into a 2.3 GB copy of library-Win64 went CPU-bound with no output at
  all and was killed at 8 minutes as a hang. It was not hung: new units brought
  new type names, the type-equality gate in ScopedResolveIsSound declined, and
  the run fell back to the WHOLE-DATABASE calls resolve -- a pass this codebase
  documents at 37 MINUTES on a 2 GB index.

  The scoped/whole line existed already, but it prints when the pass FINISHES.
  For 37 minutes there was nothing to distinguish "working" from "wedged", which
  is exactly how the note came to be filed. So the fix is diagnosis, not
  optimisation: announce the shape and the reason up front.

    1  first index of a fresh DB   -> WHOLE-DB announced BEFORE the completion
                                      line, with a reason naming the 1-in-3 limit
                                      (every file is new, so scoping is declined)
    2  edit ONE body of six        -> SCOPED announced instead
                                      (POSITIVE CONTROL for the reason text: if
                                       the announce were hard-wired to "whole",
                                       or the reason were a fixed string, this
                                       fails)
    3  ordering                    -> the "starting" line precedes the finished
                                      line in the stream, which is the entire
                                      point; a line printed afterwards would
                                      satisfy a naive text match and fix nothing

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP 'draglint_callsannounce'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$db = Join-Path $scratch 'ann.sqlite'

# SIX units, and the count matters: the scoping limit declines when a run
# rewrites one file in three or more, so step 2 needs enough files that touching
# ONE lands under it. Each calls the next, so there are real call refs to
# resolve -- with no refs the pass has nothing to report and both steps would
# pass vacuously.
$units = 'u1','u2','u3','u4','u5','u6'
function Write-Unit([string]$name, [string]$body) {
@"
unit $name;

interface

procedure ${name}Go;

implementation

procedure ${name}Helper;
begin
end;

procedure ${name}Go;
begin
$body
end;

end.
"@ -replace "`r`n","`n" -replace "`n","`r`n" | Set-Content -Path (Join-Path $scratch "$name.pas") -Encoding ascii -NoNewline
}
foreach ($u in $units) { Write-Unit $u "  ${u}Helper;" }

Push-Location C:\TEMP
try {
  # stderr carries the resolve lines; 2>&1 merges them into the stream.
  $r1 = (& $exePath index $scratch --db $db 2>&1 | Out-String)

  Check '1a. the WHOLE-DB pass is announced BEFORE it runs' `
        ($r1 -match 'calls\s+starting WHOLE-DB pass over all \d+ indexed file\(s\)')
  Check '1b. the announcement gives a REASON' `
        ($r1 -match 'calls\s+\.\.\. whole database because .+')
  # The reason must be the SPECIFIC one, recorded at the latch. A first index
  # rewrites every file, so it trips the one-in-three share -- and that latch is
  # set during accumulation, NOT by the re-check at the point of use. Naming the
  # wrong route was this suite's first failure, and it is exactly the confusion
  # the reason string exists to end, so it is asserted rather than accepted as
  # 'some reason was printed'.
  Check '1c. the reason is the SPECIFIC one (the one-in-three share)' `
        ($r1 -match 'rewrote more than one file in three \(\d+ changed, limit \d+\)') `
        $(($r1 -split "`n" | Where-Object { $_ -match 'whole database because' }) -join ' ')
  Check '1d. it says it is running rather than hung' `
        ($r1 -match 'running, not hung')

  # ORDERING. The completion line already existed; announcing AFTER the pass is
  # the bug, so a text match alone proves nothing.
  $iStart = $r1.IndexOf('starting WHOLE-DB pass')
  $iDone  = $r1.IndexOf('WHOLE DB  [')
  Check '3. the "starting" line precedes the finished line' `
        (($iStart -ge 0) -and ($iDone -ge 0) -and ($iStart -lt $iDone)) `
        "startIdx=$iStart doneIdx=$iDone"

  # --- 2. POSITIVE CONTROL: the scoped branch announces itself instead --------
  Start-Sleep -Milliseconds 1100   # mtime granularity: the skip is mtime+sha based
  # A BODY edit only: no new/withdrawn type names, so the type-equality gate
  # cannot be what decides this step.
  Write-Unit 'u3' "  u3Helper;`r`n  u3Helper;"
  $r2 = (& $exePath index $scratch --db $db 2>&1 | Out-String)

  Check '2a. one changed file of six announces a SCOPED pass' `
        ($r2 -match 'calls\s+starting SCOPED pass over \d+ changed file\(s\)') `
        $(($r2 -split "`n" | Where-Object { $_ -match 'calls\s+starting' }) -join ' ')
  Check '2b. and does NOT claim the whole database' `
        ($r2 -notmatch 'starting WHOLE-DB pass')
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
