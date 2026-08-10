<#
  run_unit_level_call_resolution.ps1 -- OPTION 4: a BARE call resolves to a
  UNIT-LEVEL (free) routine, in the call's own unit or in a unit it USES.

  WHY
  --------------------------------------------------------------------------------
  Delphi binds an unqualified call by walking outward:

      nested routines  ->  the enclosing class's methods  ->  own unit  ->  uses

  The resolver implemented the first two rungs and then stopped, so every bare
  call to a free routine stayed unresolved. Measured on drag-lint's own index
  before this change: 891 unresolved call refs name exactly one reachable
  unit-level routine -- 520 in the caller's OWN unit and 371 across a uses edge,
  with only 6 genuinely ambiguous.

  The 520 are the less obvious half and the reason this is two rungs, not one: a
  bare call inside a METHOD had its receiver typed to the enclosing class, the
  method was not found there, and resolution ended. The unit's own free routines
  were never consulted at all.

  THE TWO ASSERTIONS THAT CARRY THE DESIGN
  --------------------------------------------------------------------------------
  1. ORDERING (assertion 'Emit'). A class method SHADOWS a free routine of the
     same name. The unit-level rung therefore has to run LAST -- after the
     method chain -- or it silently retargets edges that already resolve
     correctly. `Emit` exists both as ulcaller.Emit (free) and TFoo.Emit
     (method); the bare `Emit` inside TFoo.Run must bind to the METHOD.

  2. VISIBILITY (assertion 'HiddenHelper'). An implementation-section routine is
     private to its unit however its unit is used. When this yield was first
     estimated WITHOUT a visibility check the count was 208 rather than 167, and
     the difference was 41 WRONG edges. `HiddenHelper` lives in ulcallee's
     implementation section and is called from ulcaller: no edge may appear.
     That call does not compile in real Delphi, which is the point -- the
     indexer does not compile, so only an explicit section filter stops it.

  ALSO PINNED
  --------------------------------------------------------------------------------
    * own unit beats a used unit for the same name  (`Both`)
    * a unit that is NOT used is never consulted    (`OnlyThere`, in ulother)
    * a DOTTED call never binds to a free routine   (`F.ExportedHelper`)
    * arity narrows a free overload set             (`Scaled(1)`)
    * same-unit implementation-section calls still resolve (`ExportedHelper ->
      HiddenHelper`) -- rung 1 must NOT inherit rung 2's interface-only filter

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7. Needs python on PATH for the sqlite
  read-back (same as run_nested_call_resolution.ps1).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_unitlevelcalls'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# --- the USED unit: exports two routines, hides a third ----------------------
Write-Ascii (Join-Path $scratch 'ulcallee.pas') @'
unit ulcallee;

interface

procedure ExportedHelper;
procedure Both;
function Scaled(const A: Integer): Integer; overload;
function Scaled(const A, B: Integer): Integer; overload;

implementation

procedure HiddenHelper;
begin
end;

procedure ExportedHelper;
begin
  HiddenHelper;
end;

procedure Both;
begin
end;

function Scaled(const A: Integer): Integer;
begin
  Result:= A;
end;

function Scaled(const A, B: Integer): Integer;
begin
  Result:= A + B;
end;

end.
'@

# --- a unit that is indexed but NOT used by the caller -----------------------
Write-Ascii (Join-Path $scratch 'ulother.pas') @'
unit ulother;

interface

procedure OnlyThere;

implementation

procedure OnlyThere;
begin
end;

end.
'@

# --- the CALLING unit --------------------------------------------------------
Write-Ascii (Join-Path $scratch 'ulcaller.pas') @'
unit ulcaller;

interface

uses
  ulcallee;

type
  TFoo = class
  public
    procedure Emit;
    procedure Run;
    procedure DottedProbe;
  end;

procedure CallerFree;
procedure Both;

implementation

procedure LocalOnly;
begin
end;

procedure Both;
begin
end;

procedure Emit;
begin
end;

procedure CallerFree;
begin
  LocalOnly;
  ExportedHelper;
  HiddenHelper;
  OnlyThere;
  Both;
  Scaled(1);
end;

procedure TFoo.Emit;
begin
end;

procedure TFoo.Run;
begin
  LocalOnly;
  Emit;
end;

procedure TFoo.DottedProbe;
var
  F: TFoo;
begin
  F:= nil;
  F.ExportedHelper;
end;

end.
'@

$db = Join-Path $scratch 'ulcall.sqlite'

$py = Join-Path $scratch 'edges.py'
@'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
rows = c.execute(
  "SELECT src.qualified_name, tgt.qualified_name, ce.confidence, "
  "       COALESCE(tgt.signature,'') "
  "FROM call_edges ce "
  "JOIN refs r      ON r.id   = ce.ref_id "
  "JOIN symbols src ON src.id = r.enclosing_symbol_id "
  "JOIN symbols tgt ON tgt.id = ce.target_symbol_id").fetchall()
for a, b, conf, sig in sorted(rows):
    print("%s|%s|%s|%s" % (a, b, conf, sig.replace("|", "/")))
'@ | Set-Content $py -Encoding ascii

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  $edges = @(python $py $db)
  Write-Host ("  edges:") -ForegroundColor DarkGray
  $edges | ForEach-Object { Write-Host ("    " + $_) -ForegroundColor DarkGray }

  function HasEdge([string]$src, [string]$tgt) {
    return [bool](@($edges | Where-Object { $_ -like "$src|$tgt|*" }).Count -ge 1)
  }
  function EdgeConf([string]$src, [string]$tgt) {
    $m = @($edges | Where-Object { $_ -like "$src|$tgt|*" })
    if ($m.Count -lt 1) { return '<none>' }
    return ($m[0] -split '\|')[2]
  }
  function EdgeSig([string]$src, [string]$tgt) {
    $m = @($edges | Where-Object { $_ -like "$src|$tgt|*" })
    if ($m.Count -lt 1) { return '<none>' }
    return ($m[0] -split '\|')[3]
  }

  # --- RUNG 1: the call's OWN unit ------------------------------------------
  Check 'free -> free routine in the SAME unit' `
    (HasEdge 'ulcaller.CallerFree' 'ulcaller.LocalOnly')
  Check '  ...and the edge is certain' `
    ((EdgeConf 'ulcaller.CallerFree' 'ulcaller.LocalOnly') -eq 'certain') `
    ("conf=" + (EdgeConf 'ulcaller.CallerFree' 'ulcaller.LocalOnly'))

  # THE 520-REF BUCKET: a bare call inside a METHOD reaches the unit level only
  # after the class's own methods decline. Before this change the class was
  # typed, the method was not found, and resolution ended there.
  Check 'METHOD -> free routine in the same unit (the 520 bucket)' `
    (HasEdge 'ulcaller.TFoo.Run' 'ulcaller.LocalOnly')

  # rung 1 must NOT inherit rung 2's interface-only filter: inside its own unit
  # an implementation-section routine is perfectly visible.
  Check 'same-unit IMPLEMENTATION-section routine still resolves' `
    (HasEdge 'ulcallee.ExportedHelper' 'ulcallee.HiddenHelper')

  # --- RUNG 2: units this file USES -----------------------------------------
  Check 'free -> INTERFACE routine of a USED unit' `
    (HasEdge 'ulcaller.CallerFree' 'ulcallee.ExportedHelper')

  # --- THE ORDERING GUARD ---------------------------------------------------
  # A class method shadows a free routine of the same name. If the unit-level
  # rung ever runs before the method chain, this flips and says so.
  Check 'bare Emit in TFoo.Run -> the METHOD, not the free routine' `
    (HasEdge 'ulcaller.TFoo.Run' 'ulcaller.TFoo.Emit')
  Check '  ...and NOT to the free ulcaller.Emit' `
    (-not (HasEdge 'ulcaller.TFoo.Run' 'ulcaller.Emit'))

  # --- THE VISIBILITY GUARD -------------------------------------------------
  # 41 wrong edges hid behind the absence of this check.
  Check 'implementation-section routine of ANOTHER unit does NOT bind' `
    (-not (HasEdge 'ulcaller.CallerFree' 'ulcallee.HiddenHelper'))

  # --- a unit that is not USED is not in scope ------------------------------
  Check 'routine of a NOT-USED unit does NOT bind' `
    (-not (HasEdge 'ulcaller.CallerFree' 'ulother.OnlyThere'))

  # --- own unit beats a used unit for the same name -------------------------
  Check 'own unit wins over a used unit (Both)' `
    (HasEdge 'ulcaller.CallerFree' 'ulcaller.Both')
  Check '  ...and the used unit''s Both does NOT also bind' `
    (-not (HasEdge 'ulcaller.CallerFree' 'ulcallee.Both'))

  # --- NARROW, NEVER WIDEN: a dotted call is not a bare call ----------------
  Check 'DOTTED F.ExportedHelper does NOT bind to the free routine' `
    (-not (HasEdge 'ulcaller.TFoo.DottedProbe' 'ulcallee.ExportedHelper'))

  # --- arity narrows a free overload set ------------------------------------
  # Both overloads share the qualified name ulcallee.Scaled, so only the
  # SIGNATURE can tell which one answered.
  # The existence half is NOT redundant: without it '<none>' satisfies the
  # -notlike test and the assertion passes for free while no edge exists at all.
  # It did exactly that on the RED run this test was written against.
  Check 'Scaled(1) binds to the 1-argument overload' `
    ((HasEdge 'ulcaller.CallerFree' 'ulcallee.Scaled') -and `
     ((EdgeSig 'ulcaller.CallerFree' 'ulcallee.Scaled') -notlike '*A, B*')) `
    ("sig=" + (EdgeSig 'ulcaller.CallerFree' 'ulcallee.Scaled'))
  Check '  ...and the overload choice is certain' `
    ((EdgeConf 'ulcaller.CallerFree' 'ulcallee.Scaled') -eq 'certain') `
    ("conf=" + (EdgeConf 'ulcaller.CallerFree' 'ulcallee.Scaled'))

  # --- no fabricated edges --------------------------------------------------
  $expected = @(
    'ulcallee.ExportedHelper|ulcallee.HiddenHelper',
    'ulcaller.CallerFree|ulcaller.LocalOnly',
    'ulcaller.CallerFree|ulcaller.Both',
    'ulcaller.CallerFree|ulcallee.ExportedHelper',
    'ulcaller.CallerFree|ulcallee.Scaled',
    'ulcaller.TFoo.Run|ulcaller.LocalOnly',
    'ulcaller.TFoo.Run|ulcaller.TFoo.Emit'
  )
  $unexpected = @($edges | ForEach-Object { ($_ -split '\|')[0] + '|' + ($_ -split '\|')[1] } |
                  Where-Object { $expected -notcontains $_ } | Sort-Object -Unique)
  Check 'no call edge outside the expected set (no widening)' ($unexpected.Count -eq 0) `
    ("unexpected=" + ($unexpected -join ', '))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
