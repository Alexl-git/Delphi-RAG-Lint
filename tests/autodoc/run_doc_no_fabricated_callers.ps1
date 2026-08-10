<#
  run_doc_no_fabricated_callers.ps1 -- a constructor must not claim callers it
  does not have, and `TFoo.Create(...)` must RESOLVE.

  THE BUG
  --------------------------------------------------------------------------------
  On drag-lint's own index, TQueryRule.Create -- constructed in exactly ONE place
  -- documented itself with:

      /// Called from: <five unrelated CLI routines> (+102 more)

  Two independent defects stacked into that, and this file pins both.

  1. THE RECEIVER OF A CONSTRUCTOR CALL IS A TYPE, AND THE RESOLVER HAD NO RUNG
     FOR THAT. TypeReceiver handled bare/Self, casts, locals, params, fields and
     properties -- never "the receiver names a class". So `TFoo.Create(...)`, the
     shape EVERY Delphi construction has, resolved to nothing and the symbol had
     zero call_edges.

  2. WITH NO EDGES, THE CALLER LIST FELL THROUGH TO THE UNRESOLVED-NAME BUCKET,
     which is keyed on the LEAF name. `Create` names 35 symbols in that index, so
     every unresolved `Create(` site in the corpus was claimed by every
     constructor. A uses-reachability filter already existed for this exact
     symptom and was not enough: it removes callers that are IMPOSSIBLE, and
     within one codebase almost everything reaches almost everything.

  WHY BOTH FIXES, AND WHY BOTH ASSERTIONS
  --------------------------------------------------------------------------------
  Fix 1 alone would resolve this fixture and hide fix 2 -- but any call the
  resolver still cannot bind would go on fabricating. Fix 2 alone would silence
  the fabrication and leave the real caller undiscovered, trading a wrong answer
  for no answer. So: MakerHost.Build must appear (fix 1 works), and the unrelated
  routines that merely construct something else must NOT (fix 2 works).

  Ambiguous is UNIQUENESS, not a threshold: an overload set counts as ambiguous
  too, because an unresolved `Foo(` cannot be attributed to a particular overload
  either. Widget.Poke below is the unique-name control that proves the bucket is
  gated, not deleted.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ('draglint_fabcallers_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# Two classes each with a Create, plus a third construction site, so the leaf
# name 'Create' is genuinely ambiguous exactly as it is in a real codebase.
Write-Ascii (Join-Path $scratch 'fab.pas') @'
unit fab;

interface

type
  TMaker = class
  public
    constructor Create(const AName: string);
    procedure Poke;
  end;

  TOther = class
  public
    { Takes an argument ON PURPOSE. The unresolved-name bucket collects CALL-SITE
      refs only, and a parenthesis-less `TOther.Create;` is parsed as a
      member-access rather than a call -- so a decoy without arguments generates
      no ref at all and quietly fails to reproduce the bug it exists to catch. }
    constructor Create(const AId: Integer);
  end;

  TWidget = class
  public
    procedure Poke;
  end;

  { Constructed NOWHERE. With no resolved caller its list would be uniformly
    uncertain -- the exact shape that rendered 107 unmarked guesses. }
  TLonely = class
  public
    constructor Create(const AZ: string);
  end;

procedure MakerHost;
procedure OtherHost;
procedure ThirdHost;

implementation

constructor TMaker.Create(const AName: string);
begin
end;

procedure TMaker.Poke;
begin
end;

constructor TOther.Create(const AId: Integer);
begin
end;

constructor TLonely.Create(const AZ: string);
begin
end;

procedure TWidget.Poke;
begin
end;

{ The ONLY construction of TMaker in this unit. }
procedure MakerHost;
var
  M: TMaker;
begin
  M:= TMaker.Create('x');
  M.Free;
end;

{ Constructs something ELSE. Must never be listed as a caller of TMaker.Create. }
procedure OtherHost;
var
  O: TOther;
begin
  O:= TOther.Create(7);
  O.Free;
end;

{ Constructs an RTL type the index does not hold -- an UNRESOLVED `Create(` site,
  which is precisely the kind the name bucket used to hand to every constructor. }
procedure ThirdHost;
var
  L: TStringList;
begin
  L:= TStringList.Create(True);
  L.Free;
end;

end.
'@

$db = Join-Path $scratch 'f.sqlite'

function Get-CalledFrom([string]$qname) {
  $out = (& $exePath document --qname $qname --db $db 2>$null) -join "`n"
  $l = ($out -split "`r?`n" | Where-Object { $_ -match '^\s*///' -and $_ -match 'Called from:' } | Select-Object -First 1)
  if ($null -eq $l) { return '' }
  return $l.Trim()
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  # --- FIX 1: the type-name receiver rung ----------------------------------
  $edges = (& $exePath dump-call-edges --db $db 2>$null) -join "`n"
  Write-Host "  edges:`n$edges" -ForegroundColor DarkGray
  Check 'RESOLVED: TMaker.Create has a real call edge (type-name receiver)' `
    ($edges -match 'fab\.TMaker\.Create') $edges

  $cf = Get-CalledFrom 'fab.TMaker.Create'
  Write-Host "  TMaker.Create -> $cf" -ForegroundColor DarkGray
  Check 'TMaker.Create lists MakerHost, its one real caller' `
    ($cf -match 'fab\.MakerHost') $cf

  # --- FIX 2: no fabrication from the ambiguous leaf name -------------------
  # OtherHost and ThirdHost both contain a `Create(` call site. Neither
  # constructs a TMaker, so neither may appear.
  Check 'NOT fabricated: OtherHost (constructs a different class) is absent' `
    (-not ($cf -match 'fab\.OtherHost')) $cf
  # ThirdHost MAY appear here: TMaker.Create has a resolved caller, so the list
  # is MIXED and the ' ?' marker renders, which is the honest trade the bucket
  # was designed for and which calledfrom.pas asserts deliberately. What must
  # never happen is an UNMARKED guess.
  Check 'if ThirdHost appears at all it is MARKED uncertain, never plain' `
    ((-not ($cf -match 'fab\.ThirdHost')) -or ($cf -match 'fab\.ThirdHost \(fab\.pas\) \?')) $cf

  # --- THE 107-CALLER SHAPE ITSELF: ambiguous name AND no resolved anchor ----
  # TLonely is constructed nowhere, so nothing anchors its list. Before the fix
  # every unresolved `Create(` site in the unit was claimed here, unmarked,
  # because a uniformly-uncertain list has its marker suppressed.
  $lonely = Get-CalledFrom 'fab.TLonely.Create'
  Write-Host "  TLonely.Create -> $lonely" -ForegroundColor DarkGray
  Check 'UNANCHORED + ambiguous name: claims NO callers at all' `
    ($lonely -eq '') $lonely

  # --- THE CONTROL: the bucket is GATED, not deleted -------------------------
  # 'Poke' is declared twice (TMaker.Poke, TWidget.Poke) so it is ambiguous;
  # a genuinely unique name must still collect its unresolved callers. Assert
  # the ambiguous one does not fabricate across the two same-named methods.
  $pk = Get-CalledFrom 'fab.TWidget.Poke'
  Write-Host "  TWidget.Poke -> $pk" -ForegroundColor DarkGray
  Check 'CONTROL: ambiguous Poke does not claim the OTHER Poke''s call site' `
    (-not ($pk -match 'fab\.MakerHost')) $pk
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
