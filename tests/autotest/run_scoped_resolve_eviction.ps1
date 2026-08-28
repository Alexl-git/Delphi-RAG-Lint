<#
  run_scoped_resolve_eviction.ps1 -- a prune/eviction must not throw away the
  scoped call-resolve wholesale, and must still decline it when a TYPE name is
  withdrawn.

  THE DEFECT THIS PINS (INBOX-incremental-index-hangs-on-large-db, the eviction
  half). DeleteFilesByIds latched FScopeWhole unconditionally:

      resolve: calls  ... whole database because 1 file(s) were pruned or
                          evicted, and the FK cascade took their edges outside
                          the file transactions this run recorded

  ONE evicted file bought a whole-database pass -- documented at ~37 minutes on
  a 2 GB index. The latch was there for a real reason: those files lose their
  symbols without the names ever passing through NoteScopeRemoval, so the scoped
  pass could not account for the edges the FK cascade takes.

  THE FIX IS NOT A NEW SOUNDNESS ARGUMENT. It is calling NoteScopeRemoval for
  each doomed file BEFORE the delete -- the same routine OpenFileTx already
  calls for exactly the same reason. That puts every name the file declared into
  FScopeNames (which is point 2 of ScopedResolveIsSound, unchanged) and every
  type name it declared into FScopeTypesBefore. The existing gate then decides:

    * evicted file DECLARED A TYPE -> the withdrawal test fires and the run
      still goes whole-database, now naming the type instead of the eviction.
      Point 4's indirect channel is untouched and stays fatal.
    * evicted file DECLARED NO TYPE -> it cannot participate in that channel at
      all, its own refs died with it, and every ref elsewhere that named one of
      its symbols is in FScopeNames. Scoped is sound, by the argument already
      written on ScopedResolveIsSound.

  So this guard's job is to prove BOTH branches, and to prove the second one
  gives the same answer a whole-database pass would.

  CASES
    C1  eviction of a TYPE-declaring unit still answers correctly -- the stale
        X.Ping -> uBase.TBase.Ping edge is GONE. Passes before AND after; it is
        the regression guard, not the news.
    C2  that same run still goes WHOLE-DB, and the reason now comes from the
        TYPE GATE rather than from a file count. Before the fix it said "pruned
        or evicted". The safety property, and the one that must never invert.
    C3  eviction of a unit declaring NO TYPES goes SCOPED. RED before the fix
        (it said "pruned or evicted" there too).
    C4  ORACLE for C3: the identical delta re-run with
        DRAGLINT_NO_SCOPED_RESOLVE=1 must produce a BYTE-IDENTICAL edge set.
        Without this, C3 would pass just as happily if the scoped pass had
        quietly stopped resolving anything at all.
    C5  the C3 delta really does remove an edge -- the consumer's call to the
        evicted routine is gone afterwards. Without it, C4 compares two empty
        deltas and reports agreement about nothing.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $script:fail = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
function Write-Ascii($p, $t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"),
    (New-Object System.Text.UTF8Encoding($false)))
}

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_scoped_evict'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

# The corpus is deliberately 9 units, and the arithmetic is load-bearing.
# ScopedResolveIsSound declines once the changed set reaches a third of the
# corpus, and it measures that denominator AFTER the sweep. Each delta below
# touches two files (one evicted + one touched so the run records a write), so
# the test is 2*3 < (9-1) = 6 < 8. A first draft used 7 units and got 2*3 >= 6:
# every case declined on the SIZE limit instead of the thing under test, and
# the guard reported a failure that had nothing to do with the code.
# Do not shrink it.
function Build-Corpus($dir) {
  New-Item -ItemType Directory -Path $dir -Force | Out-Null

  # Ping lives here and this file is NEVER rewritten or evicted.
  Write-Ascii (Join-Path $dir 'uBase.pas') @'
unit uBase;

interface

type
  TBase = class
  public
    procedure Ping;
  end;

implementation

procedure TBase.Ping;
begin
end;

end.
'@

  # C1/C2's victim: it DECLARES A TYPE, and declares no members of its own, so
  # 'ping' can only reach the scope through the type channel.
  Write-Ascii (Join-Path $dir 'uDoomed.pas') @'
unit uDoomed;

interface

uses
  uBase;

type
  TDoomed = class(TBase)
  end;

implementation

end.
'@

  Write-Ascii (Join-Path $dir 'uConsumer.pas') @'
unit uConsumer;

interface

uses
  uDoomed;

procedure Go;

implementation

procedure Go;
var
  X: TDoomed;
begin
  X := TDoomed.Create;
  X.Ping;
end;

end.
'@

  # C3's victim: routines only, NO type declaration anywhere in it.
  Write-Ascii (Join-Path $dir 'uProcsOnly.pas') @'
unit uProcsOnly;

interface

procedure LonelyHelper;

implementation

procedure LonelyHelper;
begin
end;

end.
'@

  Write-Ascii (Join-Path $dir 'uProcUser.pas') @'
unit uProcUser;

interface

uses
  uProcsOnly;

procedure UseIt;

implementation

procedure UseIt;
begin
  LonelyHelper;
end;

end.
'@

  foreach ($n in 1..4) {
    Write-Ascii (Join-Path $dir "uFill$n.pas") @"
unit uFill$n;

interface

type
  TFill$n = class
  public
    procedure Work$n;
  end;

procedure Drive$n;

implementation

procedure TFill$n.Work$n;
begin
end;

procedure Drive$n;
var
  F: TFill$n;
begin
  F := TFill$n.Create;
  F.Work$n;
end;

end.
"@
  }
}

$py = @'
import sqlite3, sys, os
c = sqlite3.connect(sys.argv[1])
for x in c.execute("""
    SELECT f.path, r.start_line, r.start_col, r.name_text,
           COALESCE(s.qualified_name,'?'), COALESCE(e.confidence,''),
           COALESCE(rt.qualified_name,'<NULL>')
    FROM call_edges e
    JOIN refs r ON r.id = e.ref_id
    JOIN files f ON f.id = r.file_id
    LEFT JOIN symbols s  ON s.id  = e.target_symbol_id
    LEFT JOIN symbols rt ON rt.id = e.receiver_type_symbol_id
    ORDER BY f.path, r.start_line, r.start_col, r.name_text""").fetchall():
    row = list(x); row[0] = os.path.basename(row[0])
    print('EDGE|' + '|'.join(str(i) for i in row))
'@
$pyf = Join-Path $scratch 'dump.py'
Write-Ascii $pyf $py

# One eviction run. Returns the console text so the announce line can be read.
function Run-Eviction([string]$Tag, [string]$Victim, [string]$NoScoped, [string]$Removals) {
  $dir = Join-Path $scratch $Tag
  Build-Corpus $dir
  $db = Join-Path $scratch "$Tag.sqlite"
  & $exePath index $dir --db $db 2>&1 | Out-Null

  Remove-Item (Join-Path $dir $Victim) -Force
  # One touched file, so the run records a write -- without it the run declines
  # with "recorded no file writes" and every case below would be vacuous.
  [System.IO.File]::SetLastWriteTime((Join-Path $dir 'uFill1.pas'), (Get-Date))

  Remove-Item Env:\DRAGLINT_NO_SCOPED_RESOLVE      -ErrorAction SilentlyContinue
  Remove-Item Env:\DRAGLINT_SCOPED_RESOLVE_REMOVALS -ErrorAction SilentlyContinue
  if ($NoScoped) { $env:DRAGLINT_NO_SCOPED_RESOLVE      = $NoScoped }
  if ($Removals) { $env:DRAGLINT_SCOPED_RESOLVE_REMOVALS = $Removals }
  try   { $out = & $exePath index $dir --db $db 2>&1 | Out-String }
  finally {
    Remove-Item Env:\DRAGLINT_NO_SCOPED_RESOLVE      -ErrorAction SilentlyContinue
    Remove-Item Env:\DRAGLINT_SCOPED_RESOLVE_REMOVALS -ErrorAction SilentlyContinue
  }

  return [pscustomobject]@{
    Out    = $out
    Db     = $db
    Edges  = (& python $pyf $db) -join "`n"
    Before = $null
  }
}

Push-Location C:\TEMP
try {
  # ---- C1 / C2: evicting a TYPE-declaring unit -----------------------------
  # FLIPPED 2026-08-28 (session 46). This case used to assert "still goes
  # WHOLE-DB, and the reason comes from the TYPE gate". That was the CORRECT
  # assertion while the withdrawal channel was open: a withdrawn type can change
  # what an untouched ref in an untouched file resolves to, so declining was the
  # only sound answer. WidenScopeThroughRemovedTypes now closes that channel by
  # widening instead of declining, so the eviction SCOPES -- and C1, which was
  # the regression guard here, becomes the correctness claim.
  Write-Host ''
  Write-Host 'C1/C2: evict a unit that DECLARES A TYPE' -ForegroundColor Cyan
  $t = Run-Eviction 'typed' 'uDoomed.pas' $null $null
  $announce = ($t.Out -split "`n" | Where-Object { $_ -match 'resolve: calls\s+\.\.\. whole database because|starting (SCOPED|WHOLE-DB)' }) -join ' / '
  Check 'C1 the stale X.Ping edge is gone' `
    (-not ($t.Edges -match 'uConsumer\.pas\|.*\|Ping\|')) `
    "edges:`n$($t.Edges)"
  # C1 IS AN ABSENCE, so it passes just as happily against an empty edge set --
  # a widening that broke the pass outright would look identical from here.
  Check 'C1 VACUITY: that same run still produced edges' `
    ($t.Edges -match 'EDGE\|') 'the typed-eviction run produced NO edges at all'
  Check 'C2 it now takes the SCOPED pass' ($t.Out -match 'starting SCOPED pass') $announce
  Check 'C2 and it is NOT declining on the type gate any more' `
    (-not (($t.Out -match 'withdrew the declared type name') -or ($t.Out -match 'changed the set of declared type names'))) $announce
  Check 'C2 and NOT on the old blunt eviction latch' `
    (-not ($t.Out -match 'pruned or evicted')) $announce
  Check 'C2 and NOT on the 1-in-3 size limit (the fixture would be too small)' `
    (-not ($t.Out -match 'scoping limit')) $announce

  # ---- C2p: THE POLARITY CONTROL, and the only reason C1 means anything -----
  # 'permissive' admits the scoped run but switches the widening OFF, leaving
  # the residual channel open on purpose. The stale edge MUST come back. Without
  # this, C1 would pass just as well if the widening were deleted and the edge
  # happened to be dropped for some unrelated reason.
  Write-Host ''
  Write-Host 'C2p: permissive -- the channel is real and the guard can fail' -ForegroundColor Cyan
  $tp = Run-Eviction 'typed_perm' 'uDoomed.pas' $null 'permissive'
  Check 'C2p permissive still takes the SCOPED pass' `
    ($tp.Out -match 'starting SCOPED pass') `
    (($tp.Out -split "`n" | Where-Object { $_ -match 'starting' }) -join ' / ')
  Check 'C2p and WITHOUT the widening the stale X.Ping edge SURVIVES' `
    ($tp.Edges -match 'uConsumer\.pas\|.*\|Ping\|') `
    "the channel did not reproduce -- C1 above proves nothing:`n$($tp.Edges)"

  # ---- C2o: the off switch restores the pre-2026-08-28 answer --------------
  # A hatch that quietly stopped being read would look exactly like a hatch
  # nobody needed, right up to the day someone reached for it. It must decline,
  # AND decline on the TYPE gate -- matching only 'WHOLE DB' would also pass on
  # a stale fingerprint or the 1-in-3 limit, neither of which is this hatch.
  Write-Host ''
  Write-Host 'C2o: off -- the escape hatch still works' -ForegroundColor Cyan
  $to = Run-Eviction 'typed_off' 'uDoomed.pas' $null 'off'
  Check 'C2o off goes WHOLE-DB' ($to.Out -match 'starting WHOLE-DB pass') `
    (($to.Out -split "`n" | Where-Object { $_ -match 'starting' }) -join ' / ')
  Check 'C2o and declines on the TYPE gate specifically' `
    (($to.Out -match 'withdrew the declared type name') -or ($to.Out -match 'changed the set of declared type names')) `
    (($to.Out -split "`n" | Where-Object { $_ -match 'whole database because' }) -join ' / ')
  Check 'C2o and the whole-DB answer is still correct' `
    (-not ($to.Edges -match 'uConsumer\.pas\|.*\|Ping\|')) "edges:`n$($to.Edges)"
  # THE EQUIVALENCE THAT MATTERS: widened and off must agree on the RESULT and
  # differ only in cost. This is the oracle for the whole relaxation.
  Check 'C2o ORACLE: widened and off produce IDENTICAL edge sets' `
    ($t.Edges -eq $to.Edges) "widened:`n$($t.Edges)`n`noff:`n$($to.Edges)"

  # ---- C3 / C4 / C5: evicting a unit with NO type declaration --------------
  Write-Host ''
  Write-Host 'C3/C4/C5: evict a unit that declares ONLY ROUTINES' -ForegroundColor Cyan
  $s = Run-Eviction 'procs'       'uProcsOnly.pas' $null
  $w = Run-Eviction 'procs_whole' 'uProcsOnly.pas' '1'

  $ann2 = ($s.Out -split "`n" | Where-Object { $_ -match 'resolve: calls\s+(\.\.\. whole database because|starting)' }) -join ' / '
  Check 'C3 the scoped pass is taken' ($s.Out -match 'starting SCOPED pass') $ann2
  Check 'C4 ORACLE: the whole-DB control really took the whole-DB path' `
    ($w.Out -match 'starting WHOLE-DB pass') `
    (($w.Out -split "`n" | Where-Object { $_ -match 'starting' }) -join ' / ')
  Check 'C4 scoped and whole-database edge sets are IDENTICAL' `
    ($s.Edges -eq $w.Edges) `
    "scoped:`n$($s.Edges)`n`nwhole:`n$($w.Edges)"
  Check 'C5 the delta really removed the call to the evicted routine' `
    (-not ($w.Edges -match 'LonelyHelper')) `
    "whole-db edges still name it:`n$($w.Edges)"
  Check 'C5 and the scoped run agrees it is gone' `
    (-not ($s.Edges -match 'LonelyHelper')) `
    "scoped edges still name it:`n$($s.Edges)"
  Check 'VACUITY: the runs produced edges at all' `
    (($s.Edges -match 'EDGE\|') -and ($w.Edges -match 'EDGE\|')) `
    'both edge sets empty -- the fixture is measuring nothing'
}
finally { Pop-Location }

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
