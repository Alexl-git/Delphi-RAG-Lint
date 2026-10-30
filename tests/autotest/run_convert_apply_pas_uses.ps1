<#
  run_convert_apply_pas_uses.ps1 -- 1.27.0: convert-apply reports what the
  unit's .pas still uses that the conversion map does not cover -- apply/1
  pas_uses[], dry run and --apply alike, and a text summary line per unit.

  THE CONTRACT (owner request 2026-10-10: "list methods and properties and public
  and globals not mentioned and not converted ... so we could see what else is
  there to work on"):
    * One row per (instance, member) for every member the unit's code reaches
      through a CONVERTED instance -- the same instance binding as the access-
      site rewrite (FindMemberAccessSites + BoundAccessSites) -- with kind,
      visibility, declaring_unit, declared_in (the class that DECLARES it, an
      ancestor of the From type included), every line and a count.
    * status mapped (a #link covers it), cast-refused (a cast #link covers it:
      its sites are refused), same-name (no link, the To type or an ancestor
      has the name), unmapped (the work list), not-rewritten (a link covers it,
      but convert-apply makes no .pas edit for that link shape -- a dotted path).
    * One row per global (routine / const / var / type) the unit uses from a
      unit the reconciliation REMOVES -- status global-dangling, instance ''.
      The reconciler's own dangling analysis, uncapped.
    * Always present: [] when the unit's code uses nothing of the kind.
    * Text: 'pas uses: N unmapped, M global-dangling, K same-name, J mapped,
      C cast-refused, R not-rewritten' and one line per unmapped and per
      not-rewritten member.

  Fixture written fresh under a $PID scratch folder, indexed into a scratch
  PROJECT --db there. Nothing shared is touched.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_pas_uses_$PID"
)
try {
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory $WorkDir -Force | Out-Null
function P([string]$n) { return (Join-Path $WorkDir $n) }
function W([string]$n, [string]$t) { [IO.File]::WriteAllText((P $n), (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

W 'LibBase.pas' @'
unit LibBase;

interface

uses
  Classes;

type
  TPicBase = class(TComponent)
  private
    FTag2: Integer;
  public
    procedure Refresh(A: Integer; const B: string);
  published
    property Tag2: Integer read FTag2 write FTag2;
  end;

implementation

procedure TPicBase.Refresh(A: Integer; const B: string);
begin
end;

end.
'@
W 'LibOld.pas' @'
unit LibOld;

interface

uses
  Classes, LibBase;

const
  OLD_MAX = 5;

type
  TSrcPic = class(TPersistent)
  private
    FData: string;
  published
    property Data: string read FData write FData;
  end;

  TOldMid = class(TPicBase)
  public
    procedure MidOnly;
  end;

  TPicOld = class(TOldMid)
  private
    FPicture: TSrcPic;
    FCaption: string;
    FOnPaint: TNotifyEvent;
  public
    procedure DoOld(X: Integer);
    function OldOnly: Integer;
    const TypedK: Integer = 7;
  published
    property Picture: TSrcPic read FPicture write FPicture;
    property Caption: string read FCaption write FCaption;
    property OnPaint: TNotifyEvent read FOnPaint write FOnPaint;
  end;

function OldGlobal(A: Integer): Integer;

implementation

procedure TOldMid.MidOnly;
begin
end;

procedure TPicOld.DoOld(X: Integer);
begin
end;

function TPicOld.OldOnly: Integer;
begin
  Result:= 0;
end;

function OldGlobal(A: Integer): Integer;
begin
  Result:= A;
end;

end.
'@
W 'LibNew.pas' @'
unit LibNew;

interface

uses
  Classes, LibBase;

type
  TDstGlyph = class(TPersistent)
  private
    FData: string;
  published
    property Data: string read FData write FData;
  end;

  TPicNew = class(TPicBase)
  private
    FGlyph: TDstGlyph;
    FCaption: string;
  published
    property Glyph: TDstGlyph read FGlyph write FGlyph;
    property Caption: string read FCaption write FCaption;
  end;

implementation

end.
'@
# F1Form: every status. Line numbers are asserted below -- keep the body as is.
W 'F1Form.pas' @'
unit F1Form;

interface

uses
  Classes, LibBase, LibOld;

type
  TF1Form = class(TComponent)
    pic1: TPicOld;
    procedure Run;
  end;

implementation

{$R *.dfm}

procedure TF1Form.Run;
var
  N: Integer;
begin
  pic1.Caption := 'x';
  pic1.Picture.Data := 'seed';
  pic1.Tag2 := 3;
  pic1.Refresh(1, 'two');
  pic1.DoOld(OLD_MAX);
  N := pic1.OldOnly;
  pic1.DoOld(N);
  N := OldGlobal(N);
  pic1.OnPaint := nil;
  pic1.MidOnly;
  N := pic1.TypedK;
end;

end.
'@
W 'F1Form.dfm' "object F1Form: TF1Form`n  object pic1: TPicOld`n    Caption = 'p'`n  end`nend`n"
# E0Form: converts, but its code uses nothing -- the empty-array control.
W 'E0Form.pas' @'
unit E0Form;

interface

uses
  Classes, LibBase, LibOld;

type
  TE0Form = class(TComponent)
    pic1: TPicOld;
  end;

implementation

{$R *.dfm}

end.
'@
W 'E0Form.dfm' "object E0Form: TE0Form`n  object pic1: TPicOld`n    Caption = 'p'`n  end`nend`n"
W 'P.dpr' "program P;`n`nuses`n  LibBase, LibOld, LibNew, F1Form, E0Form;`n`nbegin`nend.`n"
W 'p.rules'  "#convert TPicOld -> TPicNew`n#link Caption <- Caption`n#link Glyph <- Picture : CastA`n#unuse LibOld`n"
W 'p2.rules' "#convert TPicOld -> TPicNew`n#link Glyph <- Picture : CastA`n#unuse LibOld`n"
# p3: link shapes whose .pas sites convert-apply does NOT rewrite (a dotted To / From path)
W 'p3.rules' "#convert TPicOld -> TPicNew`n#link Glyph.Data <- Caption`n#link Caption <- Picture.Data`n"
W 'fx.castlib' "cast CastA`n  accepts TSrcPic`n  yields  TDstGlyph`n  pas     '{dst}.Assign({src});'`nend`n"

$db = P 'fx.sqlite'
& $Exe index --project (P 'P.dpr') --db $db 2>&1 | Out-Null
Check 'V the fixture PROJECT index was built' (Test-Path $db)

function Run([string]$Unit, [string]$Rules, [string[]]$Extra = @()) {
  $a = @('convert-apply', '--unit', (P $Unit), '--rules', (P $Rules), '--db', $db, '--castlib', (P 'fx.castlib')) + $Extra
  $o = (& $Exe @a 2>$null) -join "`n"
  $code = $LASTEXITCODE
  $j = $null
  if ($Extra -contains 'json') { try { $j = $o.Substring($o.IndexOf('{')) | ConvertFrom-Json } catch {} }
  return [pscustomobject]@{ Code = $code; Out = $o; J = $j }
}
function J([string]$Unit, [string]$Rules, [string[]]$Extra = @()) { return Run $Unit $Rules (@('--format', 'json') + $Extra) }
function Row($r, [string]$Inst, [string]$Member) {
  if ($null -eq $r.J -or $null -eq $r.J.pas_uses) { return $null }
  return @($r.J.pas_uses | Where-Object { $_.instance -eq $Inst -and $_.member -eq $Member }) | Select-Object -First 1
}
function Lines($row) { if ($null -eq $row) { return '<none>' }; return (@($row.lines) -join ',') }
function Show($row) { if ($null -eq $row) { return '<no row>' }; return ($row | ConvertTo-Json -Compress -Depth 4) }

# ============================== dry run ======================================
$r = J 'F1Form.pas' 'p.rules'
Check 'S0 apply/1 carries pas_uses[] (an array) and the run converts' `
  (($r.Code -eq 0) -and ($null -ne $r.J) -and ($r.J.pas_uses -is [array]) -and (@($r.J.converted).Count -eq 1)) $r.Out

$x = Row $r 'pic1' 'Caption'
Check 'M1 mapped: pic1.Caption (#link Caption <- Caption) -- property, published, TPicOld in LibOld, line 22, count 1' `
  (($null -ne $x) -and ($x.status -eq 'mapped') -and ($x.kind -eq 'property') -and ($x.visibility -eq 'published') -and
   ($x.declared_in -eq 'TPicOld') -and ($x.declaring_unit -eq 'LibOld') -and ((Lines $x) -eq '22') -and ($x.count -eq 1) -and
   ($x.from_type -eq 'TPicOld') -and ($x.to_type -eq 'TPicNew')) (Show $x)

$x = Row $r 'pic1' 'Picture'
Check 'M2 cast-refused: pic1.Picture (#link Glyph <- Picture : CastA, its site refused) -- line 23' `
  (($null -ne $x) -and ($x.status -eq 'cast-refused') -and ($x.kind -eq 'property') -and ((Lines $x) -eq '23')) (Show $x)
Check 'M2b ... and the access-site refusal it stands for is in items[]' `
  (@($r.J.items | Where-Object { $_.kind -eq 'cast-not-applied' -and $_.line -eq 23 }).Count -eq 1) (($r.J.items | ForEach-Object { $_.kind }) -join ',')

$x = Row $r 'pic1' 'Tag2'
Check 'M3 same-name, ANCESTOR-declared, an assignment: pic1.Tag2 -- declared_in TPicBase, LibBase, line 24' `
  (($null -ne $x) -and ($x.status -eq 'same-name') -and ($x.kind -eq 'property') -and ($x.declared_in -eq 'TPicBase') -and
   ($x.declaring_unit -eq 'LibBase') -and ((Lines $x) -eq '24')) (Show $x)

$x = Row $r 'pic1' 'Refresh'
Check 'M4 same-name METHOD CALL WITH ARGUMENTS: pic1.Refresh(1, ''two'') -- method, public, TPicBase, line 25' `
  (($null -ne $x) -and ($x.status -eq 'same-name') -and ($x.kind -eq 'method') -and ($x.visibility -eq 'public') -and
   ($x.declared_in -eq 'TPicBase') -and ((Lines $x) -eq '25')) (Show $x)

$x = Row $r 'pic1' 'DoOld'
Check 'M5 unmapped with its EXACT lines: pic1.DoOld -- method, public, TPicOld, lines 26,28, count 2' `
  (($null -ne $x) -and ($x.status -eq 'unmapped') -and ($x.kind -eq 'method') -and ($x.visibility -eq 'public') -and
   ($x.declared_in -eq 'TPicOld') -and ($x.declaring_unit -eq 'LibOld') -and ((Lines $x) -eq '26,28') -and ($x.count -eq 2)) (Show $x)

$x = Row $r 'pic1' 'OldOnly'
Check 'M6 unmapped on an assignment RHS: N := pic1.OldOnly -- line 27' `
  (($null -ne $x) -and ($x.status -eq 'unmapped') -and ($x.kind -eq 'method') -and ((Lines $x) -eq '27')) (Show $x)

$x = Row $r 'pic1' 'OnPaint'
Check 'M7 unmapped EVENT: pic1.OnPaint := nil -- kind event, line 30' `
  (($null -ne $x) -and ($x.status -eq 'unmapped') -and ($x.kind -eq 'event') -and ((Lines $x) -eq '30')) (Show $x)

$x = Row $r 'pic1' 'MidOnly'
Check 'M8 unmapped, declared by an INTERMEDIATE ancestor: pic1.MidOnly -- declared_in TOldMid, line 31' `
  (($null -ne $x) -and ($x.status -eq 'unmapped') -and ($x.declared_in -eq 'TOldMid') -and ($x.declaring_unit -eq 'LibOld') -and ((Lines $x) -eq '31')) (Show $x)

$x = Row $r '' 'OldGlobal'
Check 'G1 global-dangling ROUTINE from the #unuse''d LibOld: OldGlobal -- instance '''', kind routine, LibOld, line 29' `
  (($null -ne $x) -and ($x.status -eq 'global-dangling') -and ($x.kind -eq 'routine') -and ($x.declaring_unit -eq 'LibOld') -and
   ($x.from_type -eq '') -and ((Lines $x) -eq '29')) (Show $x)
$x = Row $r '' 'OLD_MAX'
Check 'G2 global-dangling CONST: OLD_MAX -- kind const, line 26' `
  (($null -ne $x) -and ($x.status -eq 'global-dangling') -and ($x.kind -eq 'const') -and ((Lines $x) -eq '26')) (Show $x)
Check 'G3 ... the same names the remove row already gives as needed_by (one analysis)' `
  ((@(@($r.J.uses | Where-Object { $_.action -eq 'remove' -and $_.unit -eq 'LibOld' })[0].needed_by | ForEach-Object { $_.name }) | Sort-Object) -join ',') -eq 'OLD_MAX,OldGlobal' `
  ($r.J.uses | ConvertTo-Json -Depth 5 -Compress)

Check 'N1 nothing else: exactly 11 rows -- no row for Data (reached through pic1.Picture, not an instance)' `
  ((@($r.J.pas_uses).Count -eq 11) -and ($null -eq (Row $r 'pic1' 'Data'))) (($r.J.pas_uses | ForEach-Object { "$($_.instance).$($_.member)=$($_.status)" }) -join ' ')

# T1 a TYPED class const has Modifiers 'typed' (EXT-E4, 1ca04f79) -- not a visibility; the row says '' (unknown), never 'typed' (cf. 14746d88 in PropTree).
$x = Row $r 'pic1' 'TypedK'
Check 'V2 typed const pic1.TypedK: kind const, visibility is not ''typed'' (unknown = empty)' `
  (($null -ne $x) -and ($x.kind -eq 'const') -and ([string]$x.visibility -eq '')) (Show $x)

# ---- discrimination: the same member, no #link -> same-name -----------------
$r2 = J 'F1Form.pas' 'p2.rules'
$x = Row $r2 'pic1' 'Caption'
Check 'D1 DISCRIMINATION: without #link Caption the same member is same-name (TPicNew has Caption), not mapped' `
  (($null -ne $x) -and ($x.status -eq 'same-name')) (Show $x)

# ---- an ancestor in ANOTHER --db (TComponent in the library index) ----------
# The project index cannot resolve TXRoot (it lives in lib\, indexed alone into
# lib.sqlite), so the member walk must continue in the store that can.
New-Item -ItemType Directory (P 'xlib'), (P 'xapp') -Force | Out-Null
W 'xlib\LibX.pas' "unit LibX;`n`ninterface`n`ntype`n  TXRoot = class`n  private`n    FXTag: Integer;`n  public`n    property XTag: Integer read FXTag write FXTag;`n  end;`n`nimplementation`n`nend.`n"
W 'xapp\AppOld.pas' "unit AppOld;`n`ninterface`n`nuses`n  LibX;`n`ntype`n  TAOld = class(TXRoot)`n  public`n    procedure OldOnly;`n  end;`n`n  TANew = class(TXRoot)`n  end;`n`nimplementation`n`nprocedure TAOld.OldOnly;`nbegin`nend;`n`nend.`n"
W 'xapp\AF.pas' "unit AF;`n`ninterface`n`nuses`n  LibX, AppOld;`n`ntype`n  TAF = class(TXRoot)`n    a1: TAOld;`n    procedure Run;`n  end;`n`nimplementation`n`n{`$R *.dfm}`n`nprocedure TAF.Run;`nbegin`n  a1.XTag := 1;`n  a1.OldOnly;`nend;`n`nend.`n"
W 'xapp\AF.dfm' "object AF: TAF`n  object a1: TAOld`n  end`nend`n"
W 'xapp\P.dpr' "program P;`n`nuses`n  AppOld, AF;`n`nbegin`nend.`n"
W 'x.rules' "#convert TAOld -> TANew`n"
& $Exe index (P 'xlib') --db (P 'xlib.sqlite') 2>&1 | Out-Null
& $Exe index --project (P 'xapp\P.dpr') --db (P 'xapp.sqlite') 2>&1 | Out-Null
$xo = (& $Exe convert-apply --unit (P 'xapp\AF.pas') --rules (P 'x.rules') --db (P 'xapp.sqlite') --db (P 'xlib.sqlite') --format json 2>$null) -join "`n"
$xr = [pscustomobject]@{ J = $null }; try { $xr.J = $xo.Substring($xo.IndexOf('{')) | ConvertFrom-Json } catch {}
$x = Row $xr 'a1' 'XTag'
Check 'X1 an ancestor declared in ANOTHER --db: a1.XTag -- same-name, declared_in TXRoot, declaring_unit LibX, line 20' `
  (($null -ne $x) -and ($x.status -eq 'same-name') -and ($x.declared_in -eq 'TXRoot') -and ($x.declaring_unit -eq 'LibX') -and ($x.kind -eq 'property') -and ((Lines $x) -eq '20')) $xo

# ---- positive control: a converted unit whose code uses nothing -------------
$e = J 'E0Form.pas' 'p.rules'
Check 'E1 POSITIVE CONTROL: E0Form converts and its pas_uses is an EMPTY array, not absent' `
  (($e.Code -eq 0) -and (@($e.J.converted).Count -eq 1) -and ($null -ne $e.J.pas_uses) -and (@($e.J.pas_uses).Count -eq 0)) $e.Out

# ---- --no-reconcile-uses: the member rows stay, the global rows go ----------
$n = J 'F1Form.pas' 'p.rules' @('--no-reconcile-uses')
Check 'R1 --no-reconcile-uses: 9 member rows, no global-dangling row (that verdict is the reconciliation''s)' `
  ((@($n.J.pas_uses).Count -eq 9) -and (@($n.J.pas_uses | Where-Object { $_.status -eq 'global-dangling' }).Count -eq 0)) (($n.J.pas_uses | ForEach-Object { "$($_.member)=$($_.status)" }) -join ' ')

# ---- text mode --------------------------------------------------------------
$t = Run 'F1Form.pas' 'p.rules'
Check 'T1 text: the summary line counts every status' `
  ($t.Out -match '(?m)^pas uses: 5 unmapped, 2 global-dangling, 2 same-name, 1 mapped, 1 cast-refused, 0 not-rewritten\s*$') $t.Out
Check 'T2 text: each unmapped member is listed with its lines' `
  (($t.Out -match '(?m)^  unmapped pic1\.DoOld \(method, public, TPicOld in LibOld\) -- lines 26, 28\s*$') -and
   ($t.Out -match '(?m)^  unmapped pic1\.MidOnly \(method, public, TOldMid in LibOld\) -- line 31\s*$')) $t.Out
$t0 = Run 'E0Form.pas' 'p.rules'
Check 'T3 text: no pas uses line when there are none' (($t0.Code -eq 0) -and -not ($t0.Out -match 'pas uses:')) $t0.Out

# ---- not-rewritten: a link covers the member, but its shape gets no .pas edit --
$r3 = J 'F1Form.pas' 'p3.rules'
$x = Row $r3 'pic1' 'Caption'
Check 'W1 not-rewritten: #link Glyph.Data <- Caption (a DOTTED To path) -- pic1.Caption, line 22, not mapped' `
  (($null -ne $x) -and ($x.status -eq 'not-rewritten') -and ($x.kind -eq 'property') -and ((Lines $x) -eq '22')) (Show $x)
$x = Row $r3 'pic1' 'Picture'
Check 'W2 not-rewritten: #link Caption <- Picture.Data (a DOTTED From path) -- pic1.Picture, line 23' `
  (($null -ne $x) -and ($x.status -eq 'not-rewritten') -and ((Lines $x) -eq '23')) (Show $x)
Check 'W3 ... and convert-apply truly makes no .pas edit for either: no access-site-rewritten item' `
  (@($r3.J.items | Where-Object { $_.kind -eq 'access-site-rewritten' }).Count -eq 0) (($r3.J.items | ForEach-Object { "$($_.kind)@$($_.line)" }) -join ',')
$t3 = Run 'F1Form.pas' 'p3.rules'
Check 'W4 text: the summary counts not-rewritten and lists each such member with its lines' `
  (($t3.Out -match '(?m)^pas uses: .*, 2 not-rewritten\s*$') -and
   ($t3.Out -match '(?m)^  not-rewritten pic1\.Caption \(property, published, TPicOld in LibOld\) -- line 22\s*$')) $t3.Out

# ---- --apply reports the same rows ------------------------------------------
$a = J 'F1Form.pas' 'p.rules' @('--apply', '--no-backup', '--no-reindex')
Check 'A1 --apply: exit 0 and pas_uses equals the dry run''s' `
  (($a.Code -eq 0) -and (@($a.J.pas_uses).Count -eq 11) -and (($a.J.pas_uses | ConvertTo-Json -Depth 5 -Compress) -eq ($r.J.pas_uses | ConvertTo-Json -Depth 5 -Compress))) `
  ("apply: " + ($a.J.pas_uses | ConvertTo-Json -Depth 5 -Compress))

# ---- SAME-NAMED CLASSES: the From class comes through the UNIT'S SCOPE ------
# Converter report 2026-10-11 (INBOX ...-pas-uses-declared-in-fmx): a VCL
# Label1: TLabel listed WordWrap as declared in FMX.StdCtrls.TLabel and Layout
# with an EMPTY kind -- the From class was looked up by BARE NAME across the
# --db stores and the first TLabel won. The library here holds both TLabels;
# FMX.StdCtrls is indexed first, so a by-name lookup lands on it (premise C0).
New-Item -ItemType Directory (P 'clib'), (P 'capp') -Force | Out-Null
W 'clib\FMX.StdCtrls.pas' "unit FMX.StdCtrls;`n`ninterface`n`ntype`n  TLabel = class`n  private`n    FWordWrap: Boolean;`n  public`n    property WordWrap: Boolean read FWordWrap write FWordWrap;`n  end;`n`nimplementation`n`nend.`n"
W 'clib\Vcl.StdCtrls.pas' "unit Vcl.StdCtrls;`n`ninterface`n`ntype`n  TTextLayout = (tlTop, tlCenter, tlBottom);`n`n  TCustomLabel = class`n  private`n    FLayout: TTextLayout;`n    FWordWrap: Boolean;`n  public`n    property Layout: TTextLayout read FLayout write FLayout;`n    property WordWrap: Boolean read FWordWrap write FWordWrap;`n  end;`n`n  TLabel = class(TCustomLabel)`n  end;`n`n  TStaticText = class`n  end;`n`nimplementation`n`nend.`n"
# one form per uses shape; with a two-line uses clause Run's body is lines 20-22
function CForm([string]$Name, [string]$Uses) {
  W "capp\$Name.pas" ("unit $Name;`n`ninterface`n`n$Uses`n`ntype`n  T$Name = class`n    Label1: TLabel;`n    procedure Run;`n  end;`n`nimplementation`n`n{`$R *.dfm}`n`nprocedure T$Name.Run;`nbegin`n  Label1.Layout := tlCenter;`n  Label1.WordWrap := True;`n  Label1.Ghost;`nend;`n`nend.`n")
  W "capp\$Name.dfm" "object ${Name}: T$Name`n  object Label1: TLabel`n  end`nend`n"
}
CForm 'CVcl'   "uses`n  Vcl.StdCtrls;"
CForm 'COrder' "uses`n  Vcl.StdCtrls, FMX.StdCtrls,`n  Vcl.StdCtrls;"
CForm 'CFmx'   "uses`n  FMX.StdCtrls;"
CForm 'CNone'  "uses`n  CVcl;"
W 'capp\P.dpr' "program P;`n`nuses`n  CVcl, COrder, CFmx, CNone;`n`nbegin`nend.`n"
W 'c.rules'  "#convert TLabel -> TStaticText`n"
W 'cq.rules' "#convert Vcl.StdCtrls.TLabel -> Vcl.StdCtrls.TStaticText`n"
& $Exe index (P 'clib') --db (P 'clib.sqlite') 2>&1 | Out-Null
& $Exe index --project (P 'capp\P.dpr') --db (P 'capp.sqlite') 2>&1 | Out-Null
$c0 = (& $Exe sql --db (P 'clib.sqlite') --query "select qualified_name from symbols where name = 'TLabel' and kind = 'class' order by id" 2>$null) -join "`n"
Check 'C0 premise: the library holds BOTH TLabels and the FMX one comes first (a by-name lookup lands on it)' `
  ($c0 -match '(?s)FMX\.StdCtrls\.TLabel.*Vcl\.StdCtrls\.TLabel') $c0
function CRun([string]$Unit, [string]$Rules) {
  $o = (& $Exe convert-apply --unit (P "capp\$Unit.pas") --rules (P $Rules) --db (P 'capp.sqlite') --db (P 'clib.sqlite') --format json 2>$null) -join "`n"
  $r = [pscustomobject]@{ J = $null; Out = $o }; try { $r.J = $o.Substring($o.IndexOf('{')) | ConvertFrom-Json } catch {}
  return $r
}
function IsVcl($x, [string]$Kind) {
  return (($null -ne $x) -and ($x.resolution -eq 'resolved') -and ($x.declaring_unit -eq 'Vcl.StdCtrls') -and
          ($x.declared_in -eq 'TCustomLabel') -and ($x.kind -eq $Kind) -and (@($x.candidates).Count -eq 0))
}
$c = CRun 'CVcl' 'c.rules'
Check 'C1 uses Vcl.StdCtrls: Label1.WordWrap is declared in Vcl.StdCtrls / TCustomLabel, not FMX.StdCtrls.TLabel' `
  (IsVcl (Row $c 'Label1' 'WordWrap') 'property') (Show (Row $c 'Label1' 'WordWrap'))
Check 'C2 ... and Label1.Layout (absent from the FMX TLabel) gets its REAL kind and declarer' `
  (IsVcl (Row $c 'Label1' 'Layout') 'property') (Show (Row $c 'Label1' 'Layout'))
$x = Row $c 'Label1' 'Ghost'
Check 'C3 a member NO class declares says so: resolution member-not-found, kind '''' -- never an empty kind as a fact' `
  (($null -ne $x) -and ($x.resolution -eq 'member-not-found') -and ($x.kind -eq '') -and ($x.declaring_unit -eq '') -and ($x.status -eq 'unmapped')) (Show $x)
$c = CRun 'COrder' 'c.rules'
Check 'C4 uses Vcl.StdCtrls, FMX.StdCtrls, Vcl.StdCtrls: the LAST entry declaring it wins (Delphi scope order) -- Vcl' `
  (IsVcl (Row $c 'Label1' 'Layout') 'property') (Show (Row $c 'Label1' 'Layout'))
$c = CRun 'CFmx' 'c.rules'
$x = Row $c 'Label1' 'WordWrap'
Check 'C5 POSITIVE CONTROL: uses FMX.StdCtrls -- WordWrap IS the FMX TLabel''s' `
  (($null -ne $x) -and ($x.resolution -eq 'resolved') -and ($x.declaring_unit -eq 'FMX.StdCtrls') -and ($x.declared_in -eq 'TLabel')) (Show $x)
$x = Row $c 'Label1' 'Layout'
Check 'C6 ... and Layout, which the FMX TLabel lacks, is member-not-found there' `
  (($null -ne $x) -and ($x.resolution -eq 'member-not-found') -and ($x.declaring_unit -eq '')) (Show $x)
# OWNER RULING 2026-10-11 (and its follow-up): a bare #convert From the unit's
# scope cannot settle is never guessed -- it is INFERRED from hard evidence or
# REFUSED. CNone's form is a .dfm, so it is a VCL form and FMX.StdCtrls.TLabel
# is excluded: the block converts as Vcl.StdCtrls.TLabel with a
# convert-class-inferred warning, and pas_uses[] rows agree with that class.
# (The refusal shape is pinned in run_convert_link_class_scope.ps1 G1-G2b.)
$c = CRun 'CNone' 'c.rules'
Check 'C7 (owner ruling 2026-10-11) no uses entry declares TLabel, the book is bare, the form is a .dfm: inferred VCL -- WordWrap is Vcl.StdCtrls / TCustomLabel, never an FMX guess' `
  (($null -ne $c.J) -and ($c.J.refused -eq $false) -and (IsVcl (Row $c 'Label1' 'WordWrap') 'property') -and
   ($c.J.qualify_fixes[0].outcome -eq 'inferred') -and ($c.J.qualify_fixes[0].chosen -eq 'Vcl.StdCtrls.TLabel')) $c.Out
$t = (& $Exe convert-apply --unit (P 'capp\CNone.pas') --rules (P 'c.rules') --db (P 'capp.sqlite') --db (P 'clib.sqlite') 2>$null) -join "`n"
Check 'C8 (owner ruling 2026-10-11) text: the warning names the inference and the line to paste' `
  ($t -match '#convert TLabel resolved to Vcl\.StdCtrls\.TLabel \(line 1\): inferred from the form file CNone\.dfm \(VCL\); qualify the line to silence this: #convert Vcl\.StdCtrls\.TLabel -> TStaticText') $t
$c = CRun 'CNone' 'cq.rules'
Check 'C9 the BOOK''s own qualification (#convert Vcl.StdCtrls.TLabel) settles what the unit''s scope cannot' `
  (IsVcl (Row $c 'Label1' 'Layout') 'property') (Show (Row $c 'Label1' 'Layout'))
$c = CRun 'CVcl' 'c.rules'
Check 'C10 every member row carries a resolution (X1''s cross-db ancestor too)' `
  ((@($c.J.pas_uses | Where-Object { $_.instance -ne '' -and -not $_.resolution }).Count -eq 0) -and ((Row $xr 'a1' 'XTag').resolution -eq 'resolved')) `
  (($c.J.pas_uses | ConvertTo-Json -Depth 4 -Compress))

# ---- capability -------------------------------------------------------------
$info = (& $Exe info --json 2>$null) -join "`n"
$ij = $null; try { $ij = $info.Substring($info.IndexOf('{')) | ConvertFrom-Json } catch {}
Check 'K info --json: capabilities.pas_uses is true' (($null -ne $ij) -and ($ij.capabilities.pas_uses -eq $true)) ''
Check 'K2 info --json: capabilities.pas_uses_resolution is true' (($null -ne $ij) -and ($ij.capabilities.pas_uses_resolution -eq $true)) ''

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
