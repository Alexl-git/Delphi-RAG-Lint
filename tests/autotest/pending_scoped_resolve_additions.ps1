<#
  pending_scoped_resolve_additions.ps1 -- a run that ADDS type names may scope
  the call-resolve, and must still produce the whole-database answer.

  WHY THIS EXISTS, AND WHY IT IS NOT A CORPUS RUN.
  tools\perf\scoped-resolve-ab.ps1 -Mode Add -AllowAdditions reports EQUIVALENT
  on ORM3: 12 added files, a 707-file index, 4x faster, byte-identical edges.
  That is evidence the relaxation is safe. It is not proof, and here it was
  actively misleading -- ORM3 does not contain the one shape that breaks it.

  ScopedResolveIsSound's point 4a names the channel, so this suite BUILDS it:

      uBase.pas      TBase declares Ping         (never rewritten)
      uConsumer.pas  X: TNew; X.Ping             (never rewritten)
      uNew.pas       TNew = class(TBase)         (ADDED by the run)

  Ping is declared in an untouched file. TNew declares no members of its own, so
  'ping' never enters FScopeNames via UpsertSymbol. uConsumer is untouched, so
  its refs are not in FScopeFiles. Adding uNew makes `X.Ping` newly resolvable
  and NOTHING in the scoped set names that ref. Measured: the whole-database
  pass binds it to uBase.TBase.Ping with confidence `certain`, and an unwidened
  scoped pass loses it.

  WHAT MAKES IT CORRECT is WidenScopeThroughAddedTypes, which pulls the member
  names reachable through each added type -- its own and its bound ancestors' --
  into the scoped name set before the pass runs.

  THIS SUITE RUNS BOTH POLARITIES, AND THAT IS THE POINT.
    widened     (DRAGLINT_SCOPED_RESOLVE_ADDITIONS=1)          MUST match whole-DB
    permissive  (DRAGLINT_SCOPED_RESOLVE_ADDITIONS=permissive) MUST NOT match
  The second is the positive control. Without it, this file would keep passing if
  the widening were deleted, if the fixture stopped constructing the hazard, or
  if some unrelated change made both runs take the same path -- every one of
  which has happened to a guard in this repo before. A guard that cannot fail is
  not a guard.

  FIXTURE SIZE IS LOAD-BEARING. ScopedResolveIsSound declines when the changed
  set reaches a third of the corpus. Five base units plus one added keeps a
  one-file delta under the limit (1*3 < 6). Do not shrink the fixture.

  Named pending_* so the battery skips it: it pins a hatch that is OFF by
  default. Promote to run_* when the additions path becomes the default.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_scoped_add'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Ascii($p,$t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"),
    (New-Object System.Text.UTF8Encoding($false)))
}

$src = Join-Path $scratch 'src'
New-Item -ItemType Directory -Path $src | Out-Null

# --- the hazard: Ping lives here, and this file is never rewritten -----------
Write-Ascii (Join-Path $src 'uBase.pas') @'
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

# --- the hazard: this ref becomes resolvable only when uNew appears ----------
Write-Ascii (Join-Path $src 'uConsumer.pas') @'
unit uConsumer;

interface

uses
  uNew;

procedure Go;

implementation

procedure Go;
var
  X: TNew;
begin
  X := TNew.Create;
  X.Ping;
end;

end.
'@

# --- filler, purely to keep the corpus over the 1-in-3 scoping limit ---------
foreach ($n in 1..3) {
Write-Ascii (Join-Path $src "uFill$n.pas") @"
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

$dbBase       = Join-Path $scratch 'base.sqlite'
$dbWhole      = Join-Path $scratch 'whole.sqlite'
$dbWidened    = Join-Path $scratch 'widened.sqlite'
$dbPermissive = Join-Path $scratch 'permissive.sqlite'

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

# Runs one index over the fixture with exactly one hatch set, and returns its
# console output. Both hatches are cleared first: a leftover from a previous run
# silently turns the next one into a repeat of it.
function RunIndex([string]$Db, [string]$NoScoped, [string]$Additions) {
  Remove-Item Env:\DRAGLINT_NO_SCOPED_RESOLVE        -ErrorAction SilentlyContinue
  Remove-Item Env:\DRAGLINT_SCOPED_RESOLVE_ADDITIONS -ErrorAction SilentlyContinue
  if ($NoScoped)   { $env:DRAGLINT_NO_SCOPED_RESOLVE        = $NoScoped  }
  if ($Additions)  { $env:DRAGLINT_SCOPED_RESOLVE_ADDITIONS = $Additions }
  try   { return (& $exePath index $src --db $Db 2>&1 | Out-String) }
  finally {
    Remove-Item Env:\DRAGLINT_NO_SCOPED_RESOLVE        -ErrorAction SilentlyContinue
    Remove-Item Env:\DRAGLINT_SCOPED_RESOLVE_ADDITIONS -ErrorAction SilentlyContinue
  }
}

Push-Location C:\TEMP
try {
  # 1. index WITHOUT uNew -- X.Ping cannot resolve yet
  & $exePath index $src --db $dbBase 2>&1 | Out-Null
  Copy-Item $dbBase $dbWhole      -Force
  Copy-Item $dbBase $dbWidened    -Force
  Copy-Item $dbBase $dbPermissive -Force

  # 2. ADD the new unit. Nothing else on disk changes.
  Write-Ascii (Join-Path $src 'uNew.pas') @'
unit uNew;

interface

uses
  uBase;

type
  TNew = class(TBase)
  end;

implementation

end.
'@

  $outWhole      = RunIndex $dbWhole      '1' ''
  $outWidened    = RunIndex $dbWidened    ''  '1'
  $outPermissive = RunIndex $dbPermissive ''  'permissive'

  # --- CONTROLS: the three runs really did take the paths they claim --------
  Check 'CONTROL: whole-DB run took the WHOLE DB path' `
        ($outWhole -match 'WHOLE DB') $outWhole
  Check 'CONTROL: widened run took the SCOPED path (the relaxation engaged)' `
        ($outWidened -match 'affected call-site ref\(s\)') $outWidened
  Check 'CONTROL: permissive run took the SCOPED path too' `
        ($outPermissive -match 'affected call-site ref\(s\)') $outPermissive

  $dumpW = & python $pyf $dbWhole      2>&1 | Out-String
  $dumpX = & python $pyf $dbWidened    2>&1 | Out-String
  $dumpP = & python $pyf $dbPermissive 2>&1 | Out-String

  # THE HAZARD MUST EXIST BEFORE IT CAN BE COMPARED. Without this, a fixture
  # that failed to build the inherited-call shape passes vacuously.
  $inherited = ($dumpW -split "`r?`n" |
      Where-Object { $_ -match '^EDGE\|uConsumer\.pas\|' -and $_ -match 'Ping' -and $_ -match 'TBase' })
  Check 'CONTROL: the whole-DB run really does bind X.Ping to the untouched TBase.Ping' `
        ($null -ne $inherited) `
        (($dumpW -split "`r?`n" | Where-Object { $_ -match 'uConsumer' }) -join "`n")

  # --- THE FIX --------------------------------------------------------------
  Check 'WIDENED addition-scoped resolve equals the whole-DB resolve' `
        ($dumpX -ceq $dumpW) "widened=$($dumpX.Length) whole=$($dumpW.Length)"
  if ($dumpX -cne $dumpW) {
    $a = ($dumpX -split "`r?`n" | Where-Object { $_ }); $b = ($dumpW -split "`r?`n" | Where-Object { $_ })
    Write-Host '      in WHOLE-DB but MISSING from widened:' -ForegroundColor DarkGray
    $b | Where-Object { $a -notcontains $_ } | Select-Object -First 10 |
      ForEach-Object { Write-Host "        $_" -ForegroundColor DarkGray }
  }

  # --- THE POSITIVE CONTROL FOR THE FIX -------------------------------------
  # Not "permissive differs somehow" -- it must be missing THIS edge, otherwise
  # the fixture has drifted onto some other disagreement and the suite above is
  # no longer testing what it says it tests.
  $permMissing = ($dumpW -split "`r?`n" | Where-Object { $_ -and ($dumpP -split "`r?`n") -notcontains $_ })
  Check 'POSITIVE CONTROL: permissive (widening off) DROPS the inherited edge' `
        (($null -ne $permMissing) -and (@($permMissing) -join "`n") -match 'uConsumer\.pas\|.*Ping\|uBase\.TBase\.Ping') `
        ("permissive is missing: " + ((@($permMissing) | Select-Object -First 5) -join '; '))
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
