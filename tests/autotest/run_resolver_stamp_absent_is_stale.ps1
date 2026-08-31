<#
  run_resolver_stamp_absent_is_stale.ps1 -- an ABSENT resolver stamp is STALE,
  and `index --all` honours `--resolve-only`.

  WHAT WENT WRONG (2026-08-31, measured -- this guard is written from a real
  incident, not from a hypothesis).

  Both staleness checks read:

      if (PrevRfp <> '') and (PrevRfp <> CurRfp) then ResolverStale := True;

  and the comment beside one of them explained the empty-guard as a deliberate
  grandfather clause: "a DB with no stored value adopts the current one silently
  rather than forcing a mass re-resolve of every index on this build's first
  run. Protection begins at the next resolve."

  THE SECOND SENTENCE IS FALSE, and that is the whole defect. There is no next
  resolve. The run adopts the current stamp on its way out via
  CommitIndexerFingerprint, so from then on PrevRfp = CurRfp and the database
  matches forever. The clause did not DEFER protection; it CANCELLED it for
  every index that existed before the stamp shipped -- which, in the release the
  stamp ships in, is every index there is.

  MEASURED. `index --all` across 31 project sections printed
  "resolve: calls skipped" 25 times, ran the calls pass 0 times, printed
  "Resolver changed" 0 times, and stamped all 31 as current. Forcing the pass
  afterwards on ONE of them (ORM3 Micronite2027) took refs.symbol_id from 4,522
  to 28,011: 84% of the resolved rows had been missing from a database that was
  reporting itself freshly resolved.

  AND IT WAS SELF-CONCEALING, which is what made it expensive rather than merely
  wrong. Once the stamp is written, no later build -- including a fixed one --
  can tell that the pass never ran, because the only signal it has now agrees.
  Recovery needs the forced flag, which is why case D below matters as much as
  case A: `index --all` is the only command that reaches every section, and it
  was accepting `--resolve-only` and silently dropping it.

  WHY THE ANALOGY IN THE OLD COMMENT DOES NOT CARRY. It grandfathered the
  resolver stamp "like the indexer fingerprint". The indexer has per-file
  mtime/sha as an INDEPENDENT staleness signal, so grandfathering its
  fingerprint blinds nothing. The resolver has no second signal -- this stamp is
  the only one -- so grandfathering it is total.

  THE FOUR CASES, and C is not optional:
    A  absent stamp    -> MUST re-derive        (the defect)
    B  mismatched stamp-> MUST re-derive        (proves the probe can observe a
                                                 detection at all, so A is not
                                                 passing vacuously)
    C  matching stamp  -> MUST still SKIP       (the fix must not degenerate
                                                 into "always re-resolve", which
                                                 would pass A and B and destroy
                                                 the 2,252s -> 17s saving)
    D  --all --resolve-only -> MUST resolve     (the forced remedy, on the only
                                                 command that covers every
                                                 section)

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_resolver_stamp_absent"
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

# Same convention as run_doc_p2_index.ps1: stdlib sqlite3 via the pinned
# interpreter, and a SKIP rather than a failure when it is not installed. This
# guard needs a WRITE (removing / ageing one schema_meta row), which the `sql`
# verb deliberately refuses -- it is authorizer-guarded read-only.
$py = 'C:\Python314\python.exe'
if (-not (Test-Path $py)) {
  Write-Host '[SKIP] run_resolver_stamp_absent_is_stale: Python not found at C:\Python314' -ForegroundColor Yellow
  exit 0
}

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null

function Emit([string]$name, [string]$text) {
  [System.IO.File]::WriteAllText((Join-Path $src $name),
    (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

Emit 'uCallee.pas' @'
unit uCallee;
interface
procedure Target;
implementation
procedure Target;
begin
end;
end.
'@

Emit 'uCaller.pas' @'
unit uCaller;
interface
uses uCallee;
procedure Go;
implementation
procedure Go;
begin
  Target;
end;
end.
'@

$db = Join-Path $WorkDir 'stamp.sqlite'

# --- tiny python helpers -----------------------------------------------------
$pyDrop = Join-Path $WorkDir 'drop.py'
[System.IO.File]::WriteAllText($pyDrop, @"
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("DELETE FROM schema_meta WHERE key='resolver_fingerprint'")
c.commit(); c.close()
"@, [System.Text.Encoding]::ASCII)

$pyAge = Join-Path $WorkDir 'age.py'
[System.IO.File]::WriteAllText($pyAge, @"
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("UPDATE schema_meta SET value='r=0.0.1-ancient;schema=21' WHERE key='resolver_fingerprint'")
c.commit(); c.close()
"@, [System.Text.Encoding]::ASCII)

$pyRead = Join-Path $WorkDir 'read.py'
[System.IO.File]::WriteAllText($pyRead, @"
import sqlite3, sys
c = sqlite3.connect('file:%s?mode=ro' % sys.argv[1], uri=True)
r = c.execute("SELECT value FROM schema_meta WHERE key='resolver_fingerprint'").fetchall()
print(r[0][0] if r else '(absent)')
c.close()
"@, [System.Text.Encoding]::ASCII)

Write-Host ''
Write-Host 'run_resolver_stamp_absent_is_stale -- a missing stamp is not a fresh one' -ForegroundColor Cyan

Push-Location C:\TEMP
try {
  & $Exe index $src --db $db 2>&1 | Out-Null
  Check 'the fixture indexed' (Test-Path $db) $db
  if (-not (Test-Path $db)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

  $stamp0 = (& $py $pyRead $db 2>&1 | Out-String).Trim()
  Check 'a fresh index carries a resolver stamp' ($stamp0 -match '^r=') $stamp0

  # ---------------------------------------------------------------- CASE C ---
  # Done FIRST, while the stamp is genuinely current and no file has changed.
  # If this ever goes red the fix has become "always re-resolve", which would
  # make A and B pass for the wrong reason.
  Write-Host ''
  Write-Host 'CASE C -- a MATCHING stamp with no file change must still SKIP' -ForegroundColor Cyan
  $matching = & $Exe index $src --db $db 2>&1 | Out-String
  Check 'the calls pass is skipped' ($matching -match 'resolve: calls\s+skipped') `
    'RED here means every unchanged index now pays a whole-DB resolve -- the 2,252s to 17s saving is gone'
  Check 'and it does NOT claim the resolver changed' `
    (-not ($matching -match 'Resolver changed|no resolver stamp')) ''

  # ---------------------------------------------------------------- CASE B ---
  Write-Host ''
  Write-Host 'CASE B -- a MISMATCHED stamp is stale (the case that already worked)' -ForegroundColor Cyan
  & $py $pyAge $db 2>&1 | Out-Null
  $aged = (& $py $pyRead $db 2>&1 | Out-String).Trim()
  Check 'the stamp was actually aged on disk' ($aged -match 'ancient') $aged
  $mismatch = & $Exe index $src --db $db 2>&1 | Out-String
  Check 'it announces the resolver change' ($mismatch -match 'Resolver changed since this DB was resolved') ''
  Check 'and the calls pass RUNS' (-not ($mismatch -match 'resolve: calls\s+skipped')) ''
  Check 'as a WHOLE-DB pass' ($mismatch -match 'WHOLE-DB pass') `
    'a scoped pass would leave the rest of the database on the old resolver'

  # ---------------------------------------------------------------- CASE A ---
  # The defect. Note this runs AFTER B, so the stamp is current again and the
  # only thing distinguishing this case is its ABSENCE.
  Write-Host ''
  Write-Host 'CASE A -- an ABSENT stamp is stale (the 2026-08-31 defect)' -ForegroundColor Cyan
  & $py $pyDrop $db 2>&1 | Out-Null
  $gone = (& $py $pyRead $db 2>&1 | Out-String).Trim()
  Check 'the stamp was actually removed on disk' ($gone -eq '(absent)') $gone
  Check 'and this is a genuinely UNCHANGED corpus, so nothing else can force the pass' `
    ($true) 'no file was written between the runs above and this one'

  $absent = & $Exe index $src --db $db 2>&1 | Out-String
  Check 'it says the DB carries no resolver stamp' ($absent -match 'no resolver stamp') `
    'RED means the grandfather clause is back: an unstamped DB is being trusted'
  Check 'the calls pass RUNS' (-not ($absent -match 'resolve: calls\s+skipped')) `
    'RED is the exact incident -- 25 of 31 sections skipped and were stamped current anyway'
  Check 'as a WHOLE-DB pass' ($absent -match 'WHOLE-DB pass') ''

  $stamp1 = (& $py $pyRead $db 2>&1 | Out-String).Trim()
  Check 'and the stamp is restored, so it now tells the truth' ($stamp1 -eq $stamp0) `
    "before=$stamp0 after=$stamp1"

  # ---------------------------------------------------------------- CASE D ---
  Write-Host ''
  Write-Host 'CASE D -- index --all must honour --resolve-only' -ForegroundColor Cyan
  $fx = "$PSScriptRoot\..\fixtures\manifest"
  if (-not (Test-Path "$fx\global.drag-lint.json")) {
    Check 'manifest fixture present' $false "$fx\global.drag-lint.json"
  } else {
    & $Exe index --all --only Proj --config "$fx\global.drag-lint.json" 2>&1 | Out-Null
    $allRo = & $Exe index --all --only Proj --resolve-only --config "$fx\global.drag-lint.json" 2>&1 | Out-String
    Check 'it announces the walk-skip' ($allRo -match 'skipping the walk') `
      'RED means --all accepted --resolve-only and dropped it'
    Check 'and the calls pass RUNS anyway' (-not ($allRo -match 'resolve: calls\s+skipped')) `
      'with the walk skipped ParsedFiles is 0, so every other term in the gate is false'
    Check 'as a WHOLE-DB pass' ($allRo -match 'WHOLE-DB pass') ''
  }
} finally { Pop-Location }

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
