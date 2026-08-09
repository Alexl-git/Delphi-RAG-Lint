<#
  run_nested_call_resolution.ps1 -- a BARE call resolves through Delphi's
  INNERMOST-FIRST lexical scope walk, so a call to a nested routine binds to the
  nested routine that the CALL SITE can actually see.

  WHY
  --------------------------------------------------------------------------------
  Nested routines became symbols in 9c64778. That alone bought +155 call edges on
  YADF for free -- a bare call inside a nested routine already looked at its
  parent's children, so SIBLING nested routines resolved. But 463 unresolved YADF
  call refs still name a nested routine, because the resolver has exactly ONE
  scope level. Delphi has a chain:

      the call site's own routine  ->  each ENCLOSING routine  ->  unit  ->  uses

  and it stops at the FIRST level that has the name. Three shapes fall out of that
  chain and none of them resolved before this test:

    1. an outer routine calling ITS OWN nested routine        (assertion 1)
    2. a doubly-nested routine calling an UNCLE, i.e. a       (assertion 2)
       routine nested in its GRANDparent
    3. a nested routine SHADOWING a method of the same name   (assertions 4/5)
       on the enclosing class

  WHY NAME-KEYED LOOKUP IS WRONG BY CONSTRUCTION (assertion 3)
  --------------------------------------------------------------------------------
  YADF.Layout.pas declares StartsWordCI FOUR times, each local to a different
  routine. Two same-named nested routines are two distinct targets, and only the
  scope walk from the call site can say which one a given bare call means. The
  Twin pair below is that shape reduced: TwinHost's call and TwinGuest's call must
  land on DIFFERENT symbols, and the CROSS edges must not exist. A resolver that
  keyed on the name would pass assertion 3's "an edge exists" half and fail the
  "no cross edge" half -- which is why both halves are asserted.

  NARROW, NEVER WIDEN (B1's rule, and assertion 6)
  --------------------------------------------------------------------------------
  Scope resolution must not manufacture edges. Assertion 5 is the guard that
  matters most: `Self.Emit` is DOTTED, so it names the class method even though a
  nested Emit is lexically nearer. If the walk ever fires on a dotted call, that
  edge flips and this test says so.

  THE TWO `inherited` ASSERTIONS ARE REGRESSION PINS, NOT TDD-DRIVEN
  --------------------------------------------------------------------------------
  They passed on first run and are recorded as such. `inherited X` is the one
  shape that looks bare (no dot, so the receiver scan reports '') while naming
  the ANCESTOR scope explicitly -- exactly the hazard the walk could create. It
  turns out the parser emits NO call ref for `inherited X;` or `inherited
  X(Args);` at all, so the resolver never sees one and needs no guard. That is
  worth pinning precisely because it is load-bearing and invisible: the day the
  parser starts emitting those refs, the walk needs an `inherited` guard, and
  these two assertions are what will say so.

  A comment in DRagLint.Index.CallResolver.TypeReceiver used to assert the
  opposite -- that `inherited M` arrived as a bare kind-1 call and resolved on
  the ancestor chain. Measuring it for this test is what showed it was wrong; the
  comment has been corrected.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7. Needs python on PATH for the sqlite
  read-back (same as run_helper_edges.ps1).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_nestedcalls'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

Write-Ascii (Join-Path $scratch 'nestcall.pas') @'
unit nestcall;

interface

type
  TBase = class
  public
    procedure Ping; virtual;
    procedure Pong(const S: string); virtual;
  end;

  TShadow = class(TBase)
  public
    procedure Emit(const S: string);
    procedure Run;
    procedure Ping; override;
    procedure Pong(const S: string); override;
  end;

procedure OuterOwn;
procedure DeepUncle;
procedure TwinHost;
procedure TwinGuest;

implementation

{ 1. an outer routine calling its OWN nested routine. }
procedure OuterOwn;

  procedure OwnHelper;
  begin
  end;

begin
  OwnHelper;
end;

{ 2. a doubly nested routine calling its UNCLE (nested in the GRANDparent). }
procedure DeepUncle;

  procedure UncleHelper;
  begin
  end;

  procedure Level1;

    procedure Level2;
    begin
      UncleHelper;
    end;

  begin
    Level2;
  end;

begin
  Level1;
end;

{ 3. two nested routines sharing a name -- each caller sees only its own. }
procedure TwinHost;

  procedure Twin;
  begin
  end;

begin
  Twin;
end;

procedure TwinGuest;

  procedure Twin;
  begin
  end;

begin
  Twin;
end;

{ 4/5. a nested routine SHADOWS a class method of the same name. }
procedure TShadow.Emit(const S: string);
begin
end;

procedure TShadow.Run;

  procedure Emit(const S: string);
  begin
  end;

begin
  Emit('x');
  Self.Emit('y');
end;

{ 6. `inherited X` names the ANCESTOR, however near a nested X is. Both the
  bare form and the `inherited X(args)` form that real code writes. }
procedure TBase.Ping;
begin
end;

procedure TBase.Pong(const S: string);
begin
end;

procedure TShadow.Ping;

  procedure Ping;
  begin
  end;

begin
  inherited Ping;
end;

procedure TShadow.Pong(const S: string);

  procedure Pong(const S: string);
  begin
  end;

begin
  inherited Pong(S);
end;

end.
'@

$db = Join-Path $scratch 'nestcall.sqlite'

$py = Join-Path $scratch 'edges.py'
@'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
rows = c.execute(
  "SELECT src.qualified_name, tgt.qualified_name, ce.confidence "
  "FROM call_edges ce "
  "JOIN refs r      ON r.id   = ce.ref_id "
  "JOIN symbols src ON src.id = r.enclosing_symbol_id "
  "JOIN symbols tgt ON tgt.id = ce.target_symbol_id").fetchall()
for a, b, conf in sorted(rows):
    print("%s|%s|%s" % (a, b, conf))
'@ | Set-Content $py -Encoding ascii

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  $edges = @(python $py $db)
  Write-Host ("  edges: " + ($edges -join '  ')) -ForegroundColor DarkGray
  function HasEdge([string]$src, [string]$tgt) {
    return [bool](@($edges | Where-Object { $_ -like "$src|$tgt|*" }).Count -ge 1)
  }
  function EdgeConf([string]$src, [string]$tgt) {
    $m = @($edges | Where-Object { $_ -like "$src|$tgt|*" })
    if ($m.Count -lt 1) { return '<none>' }
    return ($m[0] -split '\|')[2]
  }

  # --- 1. outer routine -> its OWN nested routine ----------------------------
  Check 'OuterOwn -> its own nested OwnHelper' `
    (HasEdge 'nestcall.OuterOwn' 'nestcall.OuterOwn.OwnHelper')
  Check '  ...and the edge is certain' `
    ((EdgeConf 'nestcall.OuterOwn' 'nestcall.OuterOwn.OwnHelper') -eq 'certain') `
    ("conf=" + (EdgeConf 'nestcall.OuterOwn' 'nestcall.OuterOwn.OwnHelper'))

  # --- 2. doubly nested -> UNCLE (two scopes up) -----------------------------
  Check 'Level2 -> UncleHelper (nested in the GRANDparent)' `
    (HasEdge 'nestcall.DeepUncle.Level1.Level2' 'nestcall.DeepUncle.UncleHelper')

  # the one-level cases on the same chain must not regress
  Check 'DeepUncle -> its own nested Level1' `
    (HasEdge 'nestcall.DeepUncle' 'nestcall.DeepUncle.Level1')
  Check 'Level1 -> its own nested Level2' `
    (HasEdge 'nestcall.DeepUncle.Level1' 'nestcall.DeepUncle.Level1.Level2')

  # --- 3. THE DISCRIMINATOR: same-named twins bind to their OWN --------------
  Check 'TwinHost -> TwinHost.Twin'   (HasEdge 'nestcall.TwinHost'  'nestcall.TwinHost.Twin')
  Check 'TwinGuest -> TwinGuest.Twin' (HasEdge 'nestcall.TwinGuest' 'nestcall.TwinGuest.Twin')
  Check 'no CROSS edge TwinHost -> TwinGuest.Twin' `
    (-not (HasEdge 'nestcall.TwinHost' 'nestcall.TwinGuest.Twin'))
  Check 'no CROSS edge TwinGuest -> TwinHost.Twin' `
    (-not (HasEdge 'nestcall.TwinGuest' 'nestcall.TwinHost.Twin'))

  # --- 4. SHADOWING: the bare call takes the NESTED Emit ---------------------
  Check 'bare Emit in TShadow.Run -> the NESTED Emit, not the class method' `
    (HasEdge 'nestcall.TShadow.Run' 'nestcall.TShadow.Run.Emit')

  # --- 5. NARROW: the DOTTED Self.Emit still takes the CLASS method ----------
  Check 'Self.Emit in TShadow.Run -> the CLASS method TShadow.Emit' `
    (HasEdge 'nestcall.TShadow.Run' 'nestcall.TShadow.Emit')

  # --- 6. `inherited Ping` is NOT a lexical bare call -----------------------
  # It has no dot, so the receiver scan reports '' for it and it reaches the
  # resolver looking exactly like a bare call. It is not one: `inherited` names
  # the ANCESTOR scope explicitly, so the nested Ping -- lexically nearer than
  # anything -- must not win. Whatever class-level answer this had before the
  # scope walk existed, it must still have.
  Check 'inherited Ping does NOT bind to the nested Ping' `
    (-not (HasEdge 'nestcall.TShadow.Ping' 'nestcall.TShadow.Ping.Ping'))
  Check 'inherited Pong(S) does NOT bind to the nested Pong' `
    (-not (HasEdge 'nestcall.TShadow.Pong' 'nestcall.TShadow.Pong.Pong'))

  # --- 7. no fabricated edges: every edge above is one of the expected ones --
  $expected = @(
    'nestcall.OuterOwn|nestcall.OuterOwn.OwnHelper',
    'nestcall.TShadow.Ping|nestcall.TShadow.Ping',
    'nestcall.TShadow.Ping|nestcall.TBase.Ping',
    'nestcall.TShadow.Pong|nestcall.TShadow.Pong',
    'nestcall.TShadow.Pong|nestcall.TBase.Pong',
    'nestcall.DeepUncle|nestcall.DeepUncle.Level1',
    'nestcall.DeepUncle.Level1|nestcall.DeepUncle.Level1.Level2',
    'nestcall.DeepUncle.Level1.Level2|nestcall.DeepUncle.UncleHelper',
    'nestcall.TwinHost|nestcall.TwinHost.Twin',
    'nestcall.TwinGuest|nestcall.TwinGuest.Twin',
    'nestcall.TShadow.Run|nestcall.TShadow.Run.Emit',
    'nestcall.TShadow.Run|nestcall.TShadow.Emit'
  )
  $unexpected = @($edges | ForEach-Object { ($_ -split '\|')[0] + '|' + ($_ -split '\|')[1] } |
                  Where-Object { $expected -notcontains $_ } | Sort-Object -Unique)
  Check 'no call edge outside the expected set (no widening)' ($unexpected.Count -eq 0) `
    ("unexpected=" + ($unexpected -join ', '))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
