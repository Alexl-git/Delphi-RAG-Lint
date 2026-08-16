<#
  run_scoped_resolve_equivalence.ps1 -- the SCOPED call-resolve must produce
  row-identical output to the whole-DB resolve.

  INBOX-indexer-livelock-when-two-platforms-run-concurrently. The original
  concurrency theory in that note was REFUTED; what was actually wrong was that
  an incremental index re-ran the resolve over the WHOLE database, which on a
  2 GB index looks exactly like a hang. The fix -- scoping the resolve to the
  refs that can have changed -- is landed, and `ScopedResolveIsSound` guards it.

  What did not exist was any proof the scoped path AGREES with the unscoped one.
  `DRAGLINT_NO_SCOPED_RESOLVE` exists precisely to make that a one-binary A/B,
  and no suite used it for that. This one does: same fixture, same edit, two
  DBs, and every resolved call edge plus every refs.receiver_text must match.

  That turns two landed fixes from "believed correct" into "row-identical
  proven", which is the only thing that makes the scoped path safe to build on
  (per-file resume and any future narrowing of the added-type fallback both lean
  on it).

  THE TWO PATH ASSERTIONS ARE THE POSITIVE CONTROL AND THEY ARE LOAD-BEARING.
  If a regression made ScopedResolveIsSound always return False, both runs would
  take the whole-DB path, the comparison would be whole-DB against whole-DB, and
  this suite would pass while proving nothing. So it asserts the scoped run's
  log says `affected call-site ref(s)` and the control run's says `WHOLE DB`.
  It also asserts the edge count is > 0 -- comparing two empty sets is equally
  vacuous.

  THE FIXTURE SIZE IS LOAD-BEARING, and this cost a run to discover.
  ScopedResolveIsSound declines scoping when the changed set reaches a THIRD of
  the corpus (`FScopeFiles.Count * 3 >= CountFiles`). The first version of this
  suite used 3 units and edited 1, so BOTH runs took the whole-DB path, the
  comparison was whole-DB against whole-DB, and everything passed while proving
  nothing. The two path assertions above caught it. Five units keeps one edit
  inside the limit -- do not shrink the fixture.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_scopedab'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Ascii($p,$t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"),
    (New-Object System.Text.UTF8Encoding($false)))
}

$src = Join-Path $scratch 'src'
New-Item -ItemType Directory -Path $src | Out-Null

Write-Ascii (Join-Path $src 'uCore.pas') @'
unit uCore;

interface

type
  TEngine = class
    function Compute(AValue: Integer): Integer;
    function Scale(AValue: Integer): Integer;
  end;

implementation

function TEngine.Compute(AValue: Integer): Integer;
begin
  Result := AValue * 2;
end;

function TEngine.Scale(AValue: Integer): Integer;
begin
  Result := Compute(AValue) + 1;
end;

end.
'@

Write-Ascii (Join-Path $src 'uMid.pas') @'
unit uMid;

interface

uses
  uCore;

function RunOne(AEngine: TEngine; AValue: Integer): Integer;

implementation

function RunOne(AEngine: TEngine; AValue: Integer): Integer;
begin
  Result := AEngine.Compute(AValue);
end;

end.
'@

Write-Ascii (Join-Path $src 'uTop.pas') @'
unit uTop;

interface

uses
  uCore, uMid;

function Drive(AValue: Integer): Integer;

implementation

function Drive(AValue: Integer): Integer;
var
  E: TEngine;
begin
  E := TEngine.Create;
  Result := RunOne(E, AValue) + E.Scale(AValue);
end;

end.
'@

# Two more participating units. The soundness gate declines scoping unless the
# changed set is under a THIRD of the corpus (FScopeFiles.Count * 3 < CountFiles),
# so a 3-file fixture with one edit would silently take the whole-DB path and the
# comparison below would be whole-DB against whole-DB -- vacuous. Five files keeps
# one edit comfortably inside the limit.
Write-Ascii (Join-Path $src 'uExtraA.pas') @'
unit uExtraA;

interface

uses
  uCore;

function AlphaUse(AEngine: TEngine): Integer;

implementation

function AlphaUse(AEngine: TEngine): Integer;
begin
  Result := AEngine.Compute(7);
end;

end.
'@

Write-Ascii (Join-Path $src 'uExtraB.pas') @'
unit uExtraB;

interface

uses
  uCore;

function BetaUse(AEngine: TEngine): Integer;

implementation

function BetaUse(AEngine: TEngine): Integer;
begin
  Result := AEngine.Scale(9);
end;

end.
'@

$dbScoped = Join-Path $scratch 'scoped.sqlite'
$dbWhole  = Join-Path $scratch 'whole.sqlite'

# Dump both the resolved edges and every persisted receiver, keyed so that
# re-issued symbol ids cannot register as a difference.
$py = Join-Path $scratch 'dump.py'
Write-Ascii $py @'
import sqlite3, sys
db = sys.argv[1]
c = sqlite3.connect(db)
rows = c.execute("""
    SELECT f.path, r.start_line, r.start_col, r.name_text,
           COALESCE(r.receiver_text,'<NULL>'), COALESCE(r.external_target,'<NULL>')
    FROM refs r JOIN files f ON f.id = r.file_id
    ORDER BY f.path, r.start_line, r.start_col, r.name_text""").fetchall()
for x in rows:
    print('REF|' + '|'.join(str(i) for i in x))
edges = c.execute("""
    SELECT f.path, r.start_line, r.start_col, r.name_text,
           COALESCE(s.qualified_name,'?'), COALESCE(e.confidence,'')
    FROM call_edges e
    JOIN refs r ON r.id = e.ref_id
    JOIN files f ON f.id = r.file_id
    LEFT JOIN symbols s ON s.id = e.target_symbol_id
    ORDER BY f.path, r.start_line, r.start_col""").fetchall()
for x in edges:
    print('EDGE|' + '|'.join(str(i) for i in x))
'@

Push-Location C:\TEMP
try {
  & $exePath index $src --db $dbScoped 2>&1 | Out-Null
  Copy-Item $dbScoped $dbWhole -Force

  # Edit a BODY only -- no type added or removed, so ScopedResolveIsSound holds.
  $core = Join-Path $src 'uCore.pas'
  $txt  = [System.IO.File]::ReadAllText($core).Replace('Result := AValue * 2;', 'Result := (AValue * 2) + 0;')
  Write-Ascii $core $txt

  $outScoped = & $exePath index $src --db $dbScoped 2>&1 | Out-String
  $env:DRAGLINT_NO_SCOPED_RESOLVE = '1'
  try   { $outWhole = & $exePath index $src --db $dbWhole 2>&1 | Out-String }
  finally { Remove-Item Env:\DRAGLINT_NO_SCOPED_RESOLVE -ErrorAction SilentlyContinue }

  # --- POSITIVE CONTROLS: the two runs really did take DIFFERENT paths ---
  Check 'POSITIVE CONTROL: run A took the SCOPED path' `
        ($outScoped -match 'affected call-site ref\(s\)') $outScoped
  Check 'POSITIVE CONTROL: run B took the WHOLE DB path' `
        ($outWhole -match 'WHOLE DB') $outWhole

  $dumpS = & python $py $dbScoped 2>&1 | Out-String
  $dumpW = & python $py $dbWhole  2>&1 | Out-String

  $edgeCount = (($dumpS -split "`r?`n") | Where-Object { $_.StartsWith('EDGE|') }).Count
  Check 'SANITY: there are call edges to compare (an empty A/B proves nothing)' `
        ($edgeCount -ge 3) "edges=$edgeCount"

  $refCount = (($dumpS -split "`r?`n") | Where-Object { $_.StartsWith('REF|') }).Count
  Check 'SANITY: there are refs to compare' ($refCount -ge 5) "refs=$refCount"

  # --- the actual equivalence ---
  Check 'SCOPED and WHOLE-DB resolve produce IDENTICAL refs + call edges' `
        ($dumpS -ceq $dumpW) `
        ("scoped=" + $dumpS.Length + " whole=" + $dumpW.Length)

  if ($dumpS -cne $dumpW) {
    $a = $dumpS -split "`r?`n"; $b = $dumpW -split "`r?`n"
    Write-Host '      first differing rows:' -ForegroundColor DarkGray
    for ($i = 0; $i -lt [Math]::Max($a.Count,$b.Count); $i++) {
      if ($a[$i] -cne $b[$i]) { Write-Host "        A: $($a[$i])`n        B: $($b[$i])" -ForegroundColor DarkGray; break }
    }
  }
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
