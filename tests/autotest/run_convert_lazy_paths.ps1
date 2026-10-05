<#
  run_convert_lazy_paths.ps1 -- convert-validate / convert-apply / convert-reemit
  resolve every rule path and every dotted .dfm path SEGMENT BY SEGMENT against a
  per-class member cache (engine 1.20.6, tree redesign T2b). No property tree is
  built, so no path is too deep and a real rule book validates in seconds.

  THE DEFECT. The three verbs built a depth-6 property TREE per type
  (BuildPropTree) and looked a handful of exact paths up in it. The walk
  re-expands a class on every path it recurs on, so FireDAC.Comp.Client.TFDQuery
  at depth 6 did not finish in 20 minutes, and convert-apply on a real TQuery
  unit with convrules\BDE-to-FireDAC.rules ran for hours. The depth cap also made
  a path deeper than 7 segments "not found" however real it was.

  THE CONTRACT this guard pins (fixture arms, self-contained):
    A  a 4-segment path validates; a 9-segment path through eight owned
       TPersistent parts validates with NO --depth anywhere (RED on the old
       engine: its depth-6 tree lacks it).
    B  a path through a PRIVATE property is an UNREACHABLE warning on stdout,
       exit 0 (owner ruling 2026-09-30, T2h R12 -- was "not found" in T2b),
       and proptree no longer lists a private member. A misspelled member is
       still NOT FOUND, an error, on the FROM and the TO side (B4/B5).
    C  a path THROUGH a referenced component (Conn.Params.Name, Conn a
       TComponent) fails in convert-apply, where references are leaves, and
       still passes convert-validate, which expands them -- as before.
    D  ruling R8 on the .dfm surface: a public class-typed hop (Items.Name,
       a collection's public Items) passes; a public LEAF and a protected hop
       are UNREACHABLE warnings naming the offending member (T2h), and a
       protected hop to a misspelled leaf is still NOT FOUND (D4). The PAS
       surface (psPas) has no CLI consumer.
    K  ruling R11: a descendant's private redeclaration of the ancestor's
       published property AND of its public field hides both (proptree), and
       a path to either warns naming the DESCENDANT's private member.
    U  convert-apply (json + text) and convert-reemit skip an unreachable
       #link / #default, keep converting the rest, and report it: apply/1
       unreachable[] objects (exact key set), the same message appended to the
       string warnings[] and to items[] as rule-path-unreachable, text lines on
       stdout.
    M  (fix round 1) a #mapping keeps its branch order: an unreachable target
       is stripped and the branch still wins over #else (M1/M2); an unreachable
       #when source skips the whole mapping, #else included (M3); a mapping two
       blocks apply is judged per block -- applied where reachable, warned
       naming only the other block's class (M4/M5).
    B6 a path INTO a private member stops there (Secret.Typo is UNREACHABLE).
    E  convert-apply resolves an absent, defaulted 3-segment .dfm leaf
       (P1.P2.Leaf2, default 5) -- resolved_defaults names it.
    F  owned-part recursion: the nested part's absent leaf is NOT answered from
       the parent's class (the part's block gets no Hue although the parent's
       class has Shade default 3).
    G  apply/1 has no trees_built and has classes_built = the distinct classes
       touched (4: TLazySrc, TP1, TP2, TLazyDst).
    H  convert-reemit gives byte-identical .dfm text to the 14396852 engine on
       the same block (golden captured from that engine).

  REAL-BOOK ARM (-RealBook; skipped when -LibDb is absent): pass COPIES of
  library-Win64.sqlite (-LibDb) and DMTEST.sqlite (-DmDb). A synthetic TQuery
  unit is written and indexed here; then
    R1 convert-validate of the book's TQuery block --from TQuery --to TFDQuery
       in < 30 s: exit 0, no errors, exactly 4 unreachable warnings on the
       FieldOptions.* links (a protected hop, ruling R8 + owner ruling T2h);
       with those commented out, exit 0;
    R2 convert-apply dry run of the WHOLE, UNEDITED book (every block
       validated) on the TQuery unit in < 60 s: exit 0, ok=true, qry1
       converted, no rule errors, exactly 16 unreachable warnings (lines
       274-277, 374-377, 478-485); with those commented out (a scratch copy --
       the book itself is not edited), exit 0, ok=true, qry1 converted;
    R3 (with -OldDumpDir: the old engine's `proptree --depth 6|4|2
       --refs-as-leaves --no-write-back --json` dumps, one file per type,
       '<qname>.d<N>.json') for EVERY #link/#default/#mapping path of the book,
       the new engine's found/not-found equals the old tree's, minus private
       nodes, under ruling R8. Timings are printed.

  Run from any CWD, pwsh 7. Nothing shared is touched: fixture and indexes live
  under a $PID scratch folder that is removed at the end.
#>
[CmdletBinding()]
param(
  [string]$Exe        = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir    = "$env:TEMP\drag-lint-convert-lazy-paths-$PID",
  [switch]$RealBook,
  [string]$LibDb      = '',
  [string]$DmDb       = '',
  [string]$Book       = "$PSScriptRoot\..\..\convrules\BDE-to-FireDAC.rules",
  [string]$OldDumpDir = ''
)
try {
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function P([string]$n) { return (Join-Path $WorkDir $n) }
function Json([string]$s) {
  $a = $s.IndexOf('{'); $b = $s.LastIndexOf('}')
  if ($a -lt 0 -or $b -le $a) { return $null }
  try { return ($s.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch { return $null }
}
function ErrLines([string]$s) { return ,@($s -split "`n" | Where-Object { $_ -match '^\s*line \d+: ' -and $_ -notmatch 'warning:' }) }

$fx = P 'fx'
New-Item -ItemType Directory $fx | Out-Null

# Eight owned TPersistent parts, P1..P8, so P1.P2.P3.P4.P5.P6.P7.P8.Leaf is a
# 9-segment path -- depth 8, beyond the old engine's depth-6 tree.
Write-Ascii (Join-Path $fx 'LibLazy.pas') @'
unit LibLazy;

interface

uses
  Classes;

type
  TP8 = class(TPersistent)
  private
    FLeaf: Integer;
  published
    property Leaf: Integer read FLeaf write FLeaf;
  end;

  TP7 = class(TPersistent)
  private
    FP8: TP8;
  published
    property P8: TP8 read FP8 write FP8;
  end;

  TP6 = class(TPersistent)
  private
    FP7: TP7;
  published
    property P7: TP7 read FP7 write FP7;
  end;

  TP5 = class(TPersistent)
  private
    FP6: TP6;
  published
    property P6: TP6 read FP6 write FP6;
  end;

  TP4 = class(TPersistent)
  private
    FP5: TP5;
  published
    property P5: TP5 read FP5 write FP5;
  end;

  TP3 = class(TPersistent)
  private
    FP4: TP4;
    FLeaf3: Integer;
  published
    property P4: TP4 read FP4 write FP4;
    property Leaf3: Integer read FLeaf3 write FLeaf3 default 11;
  end;

  TP2 = class(TPersistent)
  private
    FP3: TP3;
    FLeaf2: Integer;
  published
    property P3: TP3 read FP3 write FP3;
    property Leaf2: Integer read FLeaf2 write FLeaf2 default 5;
  end;

  TP1 = class(TPersistent)
  private
    FP2: TP2;
  published
    property P2: TP2 read FP2 write FP2;
  end;

  TLazyItem = class(TPersistent)
  private
    FName: string;
  published
    property Name: string read FName write FName;
  end;

  TLazyConn = class(TComponent)
  private
    FParams: TLazyItem;
  published
    property Params: TLazyItem read FParams write FParams;
  end;

  TLazySrc = class(TPersistent)
  private
    FP1: TP1;
    FSecret: Integer;
    FItems: TLazyItem;
    FProt: TLazyItem;
    FPub: Integer;
    FConn: TLazyConn;
    FShade: Integer;
    property Secret: Integer read FSecret write FSecret;
  protected
    property ProtPart: TLazyItem read FProt write FProt;
  public
    property Items: TLazyItem read FItems write FItems;
    property PubLeaf: Integer read FPub write FPub;
  published
    property P1: TP1 read FP1 write FP1;
    property Conn: TLazyConn read FConn write FConn;
    property Shade: Integer read FShade write FShade default 3;
  end;

  TLazyDst = class(TPersistent)
  private
    FTitle: Integer;
    FHue: Integer;
    FName: string;
    FDeep: Integer;
  published
    property Title: Integer read FTitle write FTitle;
    property Hue: Integer read FHue write FHue;
    property Name: string read FName write FName;
    property Deep: Integer read FDeep write FDeep;
  end;

  TPartF = class(TPersistent)
  private
    FShade: Integer;
  published
    property Shade: Integer read FShade write FShade;
  end;

  TPartT = class(TPersistent)
  private
    FHue: Integer;
  published
    property Hue: Integer read FHue write FHue;
  end;

  // Ruling R11 / T2h: a descendant's PRIVATE redeclaration shadows the
  // ancestor's member -- a published property AND a public field.
  TShBase = class(TPersistent)
  private
    FColor: Integer;
  public
    FPubF: Integer;
  published
    property Color: Integer read FColor write FColor;
  end;

  TShDesc = class(TShBase)
  private
    FPubF: Integer;
    property Color;
  end;

  // Fix round 1: #mapping branches with an unreachable target / source.
  TMapSrc = class(TPersistent)
  private
    FKind: Integer;
    FPKind: Integer;
  protected
    property PKind: Integer read FPKind write FPKind;
  published
    property Kind: Integer read FKind write FKind;
  end;

  TMapSrc2 = class(TPersistent)
  private
    FKind: Integer;
  published
    property Kind: Integer read FKind write FKind;
  end;

  TMapDst = class(TPersistent)
  private
    FA: Integer;
    FB: Integer;
    FC: Integer;
    FPubT: Integer;
  public
    property PubT: Integer read FPubT write FPubT;
  published
    property A: Integer read FA write FA;
    property B: Integer read FB write FB;
    property C: Integer read FC write FC;
  end;

  // The same member names as TMapDst, but A is only PUBLIC here.
  TMapDst2 = class(TPersistent)
  private
    FA: Integer;
  public
    property A: Integer read FA write FA;
  end;

  TUnrDst = class(TPersistent)
  private
    FTitle: Integer;
    FPubTo: Integer;
  public
    property PubTo: Integer read FPubTo write FPubTo;
  published
    property Title: Integer read FTitle write FTitle;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $fx 'LazyForm.pas') @'
unit LazyForm;

interface

uses
  Classes, LibLazy;

type
  TLazyForm = class(TForm)
    src1: TLazySrc;
  end;

implementation

{$R *.dfm}

end.
'@

Write-Ascii (Join-Path $fx 'MapForm.pas') @'
unit MapForm;

interface

uses
  Classes, LibLazy;

type
  TMapForm = class(TForm)
    m1: TMapSrc;
    m2: TMapSrc2;
  end;

implementation

{$R *.dfm}

end.
'@

Write-Ascii (Join-Path $fx 'MapForm.dfm') @'
object MapForm: TMapForm
  object m1: TMapSrc
    Kind = 1
  end
  object m2: TMapSrc2
    Kind = 1
  end
end
'@

Write-Ascii (Join-Path $fx 'LazyForm.dfm') @'
object LazyForm: TLazyForm
  object src1: TLazySrc
  end
end
'@

$db = P 'fx.sqlite'
$idx = & $Exe index $fx --db $db 2>&1
Check 'V the fixture index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE; $($idx -join ' | ')"

function Book([string]$Name, [string]$Body) { Write-Ascii (P $Name) $Body; return (P $Name) }
function Validate([string]$Rules, [string]$From = 'LibLazy.TLazySrc', [string]$To = 'LibLazy.TLazyDst') {
  $o = (& $Exe convert-validate --rules $Rules --from $From --to $To --db $db 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
# T2h: STDOUT only -- pins the stream the unreachable warnings are printed on.
function ValidateOut([string]$Rules, [string]$From = 'LibLazy.TLazySrc', [string]$To = 'LibLazy.TLazyDst') {
  $o = (& $Exe convert-validate --rules $Rules --from $From --to $To --db $db 2>$null) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
# The one warning text (owner ruling 2026-09-30, R12), for a rule on line $L.
function UnrMsg([int]$L, [string]$Path, [string]$Member, [string]$Vis, [string]$Cls) {
  return ('line {0}: warning: {1}: {2} is {3} in {4}; never applied unless a descendant class changes its visibility' -f $L, $Path, $Member, $Vis, $Cls)
}
function HasLine([string]$Out, [string]$Line) { return (@($Out -split "`r?`n" | Where-Object { $_.Trim() -ceq $Line }).Count -eq 1) }
# JSON is read from STDOUT only: the engine's stderr preamble can land inside the
# document when the two streams are merged.
function Apply([string]$Rules, [string[]]$Extra = @()) {
  $o = if ($Extra -contains 'json') { (& $Exe convert-apply --unit (Join-Path $fx 'LazyForm.pas') --rules $Rules --db $db @Extra 2>$null) -join "`n" }
       else { (& $Exe convert-apply --unit (Join-Path $fx 'LazyForm.pas') --rules $Rules --db $db @Extra 2>&1) -join "`n" }
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
$Hdr = '#convert LibLazy.TLazySrc -> LibLazy.TLazyDst, LibLazy'

# ---- R15: a path INTO a private member stops there ------------------------
$r = ValidateOut (Book 'privtail.rules' "#link Title <- Secret.Typo`n")
Check 'B6 Secret.Typo: UNREACHABLE naming Secret (the tail past a private member is not checked)' `
  (($r.Code -eq 0) -and (HasLine $r.Out (UnrMsg 1 'Secret.Typo' 'Secret' 'private' 'LibLazy.TLazySrc'))) $r.Out

# ---- A: depth is no limit -------------------------------------------------
$r = Validate (Book 'a4.rules' "#link Title <- P1.P2.P3.Leaf3`n")
Check 'A1 a 4-segment path validates' (($r.Code -eq 0) -and ($r.Out -match '(?m)^OK')) $r.Out
$r = Validate (Book 'a9.rules' "#link Title <- P1.P2.P3.P4.P5.P6.P7.P8.Leaf`n")
Check 'A2 a 9-segment path validates with no --depth (old engine: not found at depth 6)' (($r.Code -eq 0) -and ($r.Out -match '(?m)^OK')) $r.Out
$r = Validate (Book 'a9bad.rules' "#link Title <- P1.P2.P3.P4.P5.P6.P7.P8.NoLeaf`n")
Check 'A3 control: a 9-segment path with a bogus leaf fails' `
  (($r.Code -eq 1) -and ($r.Out -match 'link FromPath not found in --from tree: P1\.P2\.P3\.P4\.P5\.P6\.P7\.P8\.NoLeaf')) $r.Out

# ---- B: private never resolves --------------------------------------------
# T2h (owner ruling 2026-09-30, R12): a path through a member that EXISTS but is
# inaccessible is a WARNING, on STDOUT, exit 0 -- no longer "not found".
$r = ValidateOut (Book 'priv.rules' "#link Title <- Secret`n")
Check 'B1 a path to a PRIVATE property warns (stdout), exit 0, OK -- not "not found"' `
  (($r.Code -eq 0) -and (HasLine $r.Out (UnrMsg 1 'Secret' 'Secret' 'private' 'LibLazy.TLazySrc')) -and ($r.Out -match '(?m)^OK') -and `
   -not ($r.Out -match 'not found')) $r.Out
$r = Validate (Book 'nf-from.rules' "#link Title <- Secrett`n")
Check 'B4 NOT-FOUND control, FROM side: a misspelled member is still an error (exit 1)' `
  (($r.Code -eq 1) -and ($r.Out -match 'link FromPath not found in --from tree: Secrett') -and -not ($r.Out -match 'warning:')) $r.Out
$r = Validate (Book 'nf-to.rules' "#link Titel <- Shade`n")
Check 'B5 NOT-FOUND control, TO side: a misspelled member is still an error (exit 1)' `
  (($r.Code -eq 1) -and ($r.Out -match 'link ToPath not found in --to tree: Titel') -and -not ($r.Out -match 'warning:')) $r.Out
$pt = (& $Exe proptree --qname LibLazy.TLazySrc --refs-as-leaves --no-write-back --json --db $db 2>$null) -join "`n"
$pj = Json $pt
$paths = @($pj.properties | ForEach-Object { $_.path })
Check 'B2 proptree lists no private member (Secret, FP1, FSecret gone; P1 kept)' `
  (($null -ne $pj) -and ($paths -contains 'P1') -and -not ($paths -contains 'Secret') -and -not ($paths -contains 'FP1') -and -not ($paths -contains 'FSecret') -and `
   (@($pj.properties | Where-Object { $_.visibility -eq 'private' }).Count -eq 0)) ($paths -join ',')
Check 'B3 proptree still lists the protected and public members (ProtPart, Items, PubLeaf)' `
  (($paths -contains 'ProtPart') -and ($paths -contains 'Items') -and ($paths -contains 'PubLeaf')) ($paths -join ',')

# ---- C: a path through a referenced component -----------------------------
$cr = Book 'conn.rules' "$Hdr`n#link Name <- Conn.Params.Name`n"
$r = Apply $cr
Check 'C1 convert-apply: Conn.Params.Name (through a TComponent reference) is not found' `
  (($r.Code -eq 1) -and ($r.Out -match 'line 2: link FromPath not found in --from tree: Conn\.Params\.Name')) $r.Out
$r = Validate (Book 'connv.rules' "#link Name <- Conn.Params.Name`n")
Check 'C2 convert-validate (references expanded, as before): it validates' (($r.Code -eq 0) -and ($r.Out -match '(?m)^OK')) $r.Out
$r = Apply (Book 'conn0.rules' "$Hdr`n#link Name <- Conn`n")
Check 'C3 control: the reference itself (Conn) is a leaf and resolves' (-not ($r.Out -match 'not found')) $r.Out

# ---- D: ruling R8 on the .dfm surface --------------------------------------
$r = Validate (Book 'coll.rules' "#link Name <- Items.Name`n")
Check 'D1 a public class-typed hop to a published leaf (Items.Name) passes' (($r.Code -eq 0) -and ($r.Out -match '(?m)^OK')) $r.Out
$r = ValidateOut (Book 'pub.rules' "#link Title <- PubLeaf`n")
Check 'D2 a public LEAF on the .dfm surface warns (unreachable), exit 0' `
  (($r.Code -eq 0) -and (HasLine $r.Out (UnrMsg 1 'PubLeaf' 'PubLeaf' 'public' 'LibLazy.TLazySrc')) -and -not ($r.Out -match 'not found')) $r.Out
$r = ValidateOut (Book 'prot.rules' "#link Name <- ProtPart.Name`n")
Check 'D3 a protected hop on the .dfm surface warns, naming the hop, exit 0' `
  (($r.Code -eq 0) -and (HasLine $r.Out (UnrMsg 1 'ProtPart.Name' 'ProtPart' 'protected' 'LibLazy.TLazySrc')) -and -not ($r.Out -match 'not found')) $r.Out
$r = Validate (Book 'prot-nf.rules' "#link Name <- ProtPart.Nme`n")
Check 'D4 NOT-FOUND wins: a protected hop to a misspelled leaf is an error, not a warning' `
  (($r.Code -eq 1) -and ($r.Out -match 'link FromPath not found in --from tree: ProtPart\.Nme') -and -not ($r.Out -match 'warning:')) $r.Out

# ---- K: ruling R11 -- a private redeclaration shadows; the warning names it --
$pt = (& $Exe proptree --qname LibLazy.TShDesc --refs-as-leaves --no-write-back --json --db $db 2>$null) -join "`n"
$kj = Json $pt
$kp = @($kj.properties | ForEach-Object { $_.path })
Check 'K1 proptree TShDesc: neither Color nor FPubF (the private redeclarations shadow the ancestor''s)' `
  (($null -ne $kj) -and -not ($kp -contains 'Color') -and -not ($kp -contains 'FPubF')) ($kp -join ',')
$pt = (& $Exe proptree --qname LibLazy.TShBase --refs-as-leaves --no-write-back --json --db $db 2>$null) -join "`n"
$bp = @((Json $pt).properties | ForEach-Object { $_.path })
Check 'K2 positive control: proptree TShBase lists Color and the public field FPubF' `
  (($bp -contains 'Color') -and ($bp -contains 'FPubF')) ($bp -join ',')
$r = ValidateOut (Book 'r11p.rules' "#link Title <- Color`n") 'LibLazy.TShDesc' 'LibLazy.TLazyDst'
Check 'K3 R11 property: a path to the shadowed Color warns, naming the DESCENDANT''s private member' `
  (($r.Code -eq 0) -and (HasLine $r.Out (UnrMsg 1 'Color' 'Color' 'private' 'LibLazy.TShDesc'))) $r.Out
$r = ValidateOut (Book 'r11f.rules' "#link Title <- FPubF`n") 'LibLazy.TShDesc' 'LibLazy.TLazyDst'
Check 'K4 R11 FIELD: a path to the shadowed public field warns, naming the DESCENDANT''s private field' `
  (($r.Code -eq 0) -and (HasLine $r.Out (UnrMsg 1 'FPubF' 'FPubF' 'private' 'LibLazy.TShDesc'))) $r.Out
$r = ValidateOut (Book 'r11fb.rules' "#link Title <- FPubF`n") 'LibLazy.TShBase' 'LibLazy.TLazyDst'
Check 'K5 control: on TShBase the same field is the ancestor''s PUBLIC field (a public leaf on the .dfm surface)' `
  (($r.Code -eq 0) -and (HasLine $r.Out (UnrMsg 1 'FPubF' 'FPubF' 'public' 'LibLazy.TShBase'))) $r.Out

# ---- U: convert-apply / convert-reemit skip an unreachable rule and say so --
$UHdr = '#convert LibLazy.TLazySrc -> LibLazy.TUnrDst, LibLazy'
$ub = Book 'unr.rules' "$UHdr`n#link Title <- Secret`n#default PubTo = 4`n#link Title <- Shade`n"
$r = Apply $ub @('--format', 'json')
$uj = Json $r.Out
$UMsg2 = UnrMsg 2 'Secret' 'Secret' 'private' 'LibLazy.TLazySrc'
$UMsg3 = UnrMsg 3 'PubTo' 'PubTo' 'public' 'LibLazy.TUnrDst'
$UKeys = 'class,line,member,message,path,reason,visibility'
Check 'U1 convert-apply --format json: exit 0, ok=true, the unit still converts (src1), stdout is ONE JSON document' `
  (($r.Code -eq 0) -and ($null -ne $uj) -and $uj.ok -and (@($uj.converted | Where-Object { $_ -match '^src1: ' }).Count -eq 1) -and `
   $r.Out.Trim().StartsWith('{') -and $r.Out.Trim().EndsWith('}')) $r.Out
$un = @($uj.unreachable)
Check 'U2 apply/1 unreachable[]: 2 objects, keys EXACTLY line,path,member,visibility,class,reason,message' `
  (($un.Count -eq 2) -and (@($un | Where-Object { ((@($_.PSObject.Properties.Name) | Sort-Object) -join ',') -ne $UKeys }).Count -eq 0)) ($un | ConvertTo-Json -Compress)
$u2 = @($un | Where-Object { $_.line -eq 2 })
$u3 = @($un | Where-Object { $_.line -eq 3 })
Check 'U3 unreachable[] values: line 2 Secret private in TLazySrc; line 3 PubTo public in TUnrDst; reason=unreachable; message = the text line' `
  (($u2.Count -eq 1) -and ($u2[0].path -eq 'Secret') -and ($u2[0].member -eq 'Secret') -and ($u2[0].visibility -eq 'private') -and `
   ($u2[0].class -eq 'LibLazy.TLazySrc') -and ($u2[0].reason -eq 'unreachable') -and ($u2[0].message -ceq $UMsg2) -and `
   ($u3.Count -eq 1) -and ($u3[0].path -eq 'PubTo') -and ($u3[0].visibility -eq 'public') -and ($u3[0].class -eq 'LibLazy.TUnrDst') -and ($u3[0].message -ceq $UMsg3)) `
  ($un | ConvertTo-Json -Compress)
$uw = @($uj.warnings)
Check 'U4 apply/1 warnings[] stays an array of STRINGS and carries each unreachable message' `
  (($uw.Count -ge 2) -and (@($uw | Where-Object { $_ -isnot [string] }).Count -eq 0) -and ($uw -ccontains $UMsg2) -and ($uw -ccontains $UMsg3)) ($uw | ConvertTo-Json -Compress)
Check 'U5 items[] mirrors them as kind rule-path-unreachable (field warnings, rule_line)' `
  ((@($uj.items | Where-Object { $_.kind -eq 'rule-path-unreachable' -and $_.field -eq 'warnings' -and @(2, 3) -contains $_.rule_line }).Count -eq 2)) ($uj.items | ConvertTo-Json -Compress -Depth 4)
Check 'U6 the reachable rule on line 4 still ran (Shade default 3 carried to Title)' `
  (@($uj.resolved_defaults | Where-Object { $_.from_path -eq 'Shade' -and $_.to_path -eq 'Title' -and $_.value -eq '3' }).Count -eq 1) ($uj.resolved_defaults | ConvertTo-Json -Compress -Depth 4)
$r = (& $Exe convert-apply --unit (Join-Path $fx 'LazyForm.pas') --rules $ub --db $db 2>$null) -join "`n"
$uc = $LASTEXITCODE
Check 'U7 text mode: exit 0; each warning is a line on STDOUT; the skipped #default wrote nothing (no PubTo in the plan)' `
  (($uc -eq 0) -and (HasLine $r $UMsg2) -and (HasLine $r $UMsg3) -and -not ($r -match 'PubTo = 4')) $r
Write-Ascii (P 'unr.dfm') @'
object src1: TLazySrc
  Shade = 7
end
'@
$o = (& $Exe convert-reemit --from-block (P 'unr.dfm') --rules $ub --from LibLazy.TLazySrc --to LibLazy.TUnrDst --db $db 2>$null) -join "`n"
$ej = Json $o
Check 'U8 convert-reemit skips the unreachable #default (no PubTo) and lists it in unreachable[]; Title = 7 still carried' `
  (($null -ne $ej) -and $ej.ok -and -not ([string]$ej.dfm -match 'PubTo') -and ([string]$ej.dfm -match '(?m)^  Title = 7\r?$') -and `
   (@($ej.unreachable | Where-Object { $_.line -eq 3 -and $_.message -ceq $UMsg3 }).Count -eq 1)) $o

# ---- M: #mapping branch order survives an unreachable path (fix round 1) ---
$MHdr = '#convert LibLazy.TMapSrc -> LibLazy.TMapDst, LibLazy'
function Reemit([string]$Dfm, [string]$Rules, [string]$From = 'LibLazy.TMapSrc', [string]$To = 'LibLazy.TMapDst') {
  $o = (& $Exe convert-reemit --from-block $Dfm --rules $Rules --from $From --to $To --db $db 2>$null) -join "`n"
  return (Json $o)
}
Write-Ascii (P 'k1.dfm') "object s1: TMapSrc`n  Kind = 1`nend`n"
Write-Ascii (P 'k2.dfm') "object s1: TMapSrc`n  Kind = 2`nend`n"
$mb = Book 'kmap.rules' "$MHdr`n#apply KMap`n#mapping KMap`n#mapping KMap #when Kind = 1 -> A = 11, PubT = 12`n#mapping KMap #when Kind = 2 -> B = 22`n#mapping KMap #else -> C = 99`n"
$j = Reemit (P 'k1.dfm') $mb
$d = if ($j) { [string]$j.dfm } else { '' }
Check 'M1 branch 1 matches: its REACHABLE target is set (A = 11), the unreachable one is not (no PubT), and #else does NOT fire (no C)' `
  (($null -ne $j) -and $j.ok -and ($d -match '(?m)^  A = 11\r?$') -and -not ($d -match 'PubT') -and -not ($d -match 'C = 99') -and -not ($d -match 'B = 22') -and `
   (@($j.unreachable | Where-Object { $_.line -eq 4 -and $_.path -eq 'PubT' -and $_.class -eq 'LibLazy.TMapDst' }).Count -eq 1)) ($d -replace "`r`n", '|')
$j = Reemit (P 'k2.dfm') $mb
$d = if ($j) { [string]$j.dfm } else { '' }
Check 'M2 control: branch 2 still matches its own value (B = 22), nothing else' `
  (($null -ne $j) -and ($d -match '(?m)^  B = 22\r?$') -and -not ($d -match 'A = 11') -and -not ($d -match 'C = 99')) ($d -replace "`r`n", '|')
$wb = Book 'wmap.rules' "$MHdr`n#apply WMap`n#mapping WMap`n#mapping WMap #when PKind = 1 -> A = 11`n#mapping WMap #else -> C = 99`n"
$j = Reemit (P 'k1.dfm') $wb
$d = if ($j) { [string]$j.dfm } else { '' }
Check 'M3 unreachable #when SOURCE: the WHOLE mapping is skipped -- no branch, NO #else (no A, no C); warned naming PKind' `
  (($null -ne $j) -and $j.ok -and -not ($d -match 'A = 11') -and -not ($d -match 'C = 99') -and `
   (@($j.unreachable | Where-Object { $_.line -eq 4 -and $_.member -eq 'PKind' -and $_.visibility -eq 'protected' }).Count -eq 1)) ($d -replace "`r`n", '|')
# Two blocks share ONE mapping line: reachable in block 1 (TMapDst.A published),
# unreachable in block 2 (TMapDst2.A public).
$sb = Book 'smap.rules' ("#convert LibLazy.TMapSrc -> LibLazy.TMapDst, LibLazy`n#apply SMap`n" +
  "#convert LibLazy.TMapSrc2 -> LibLazy.TMapDst2, LibLazy`n#apply SMap`n#mapping SMap`n#mapping SMap #when Kind = 1 -> A = 5`n")
$o = (& $Exe convert-apply --unit (Join-Path $fx 'MapForm.pas') --rules $sb --db $db --format json 2>$null) -join "`n"
$sj = Json $o
Check 'M4 shared mapping, JSON: exit 0; exactly ONE unreachable record, naming block 2''s class (LibLazy.TMapDst2) only' `
  (($LASTEXITCODE -eq 0) -and ($null -ne $sj) -and $sj.ok -and (@($sj.unreachable).Count -eq 1) -and ($sj.unreachable[0].line -eq 6) -and `
   ($sj.unreachable[0].class -eq 'LibLazy.TMapDst2') -and ($sj.unreachable[0].message -ceq (UnrMsg 6 'A' 'A' 'public' 'LibLazy.TMapDst2'))) $o
$o = (& $Exe convert-apply --unit (Join-Path $fx 'MapForm.pas') --rules $sb --db $db 2>$null) -join "`n"
$b1 = [regex]::Match($o, '(?s)object m1: TMapDst\r?\n(.*?)\bend\b')
$b2 = [regex]::Match($o, '(?s)object m2: TMapDst2\r?\n(.*?)\bend\b')
Check 'M5 shared mapping, dry-run plan: block 1 still applies it (m1 gets A = 5); block 2 does not (m2 has no A)' `
  ($b1.Success -and ($b1.Groups[1].Value -match 'A = 5') -and $b2.Success -and -not ($b2.Groups[1].Value -match 'A = 5')) $o

# ---- E + G: resolved default through a 3-segment path; classes_built -------
$r = Apply (Book 'deep.rules' "$Hdr`n#link Deep <- P1.P2.Leaf2`n") @('--format', 'json')
$j = Json $r.Out
$rd = @($j.resolved_defaults | Where-Object { $_.from_path -eq 'P1.P2.Leaf2' })
Check 'E1 dry run ok' (($r.Code -eq 0) -and ($null -ne $j) -and $j.ok) $r.Out
Check 'E2 resolved_defaults names P1.P2.Leaf2 -> Deep = 5' `
  (($rd.Count -eq 1) -and ($rd[0].to_path -eq 'Deep') -and ($rd[0].value -eq '5')) ($j.resolved_defaults | ConvertTo-Json -Compress -Depth 4)
Check 'G1 apply/1 has no trees_built key' (($null -ne $j) -and -not ($j.PSObject.Properties.Name -contains 'trees_built')) $r.Out
Check 'G2 apply/1 classes_built = 4 (TLazySrc, TP1, TP2, TLazyDst)' `
  (($null -ne $j) -and ($j.classes_built -eq 4)) "classes_built=$(if ($j) { $j.classes_built } else { '<no json>' })"

# ---- F + H: convert-reemit ------------------------------------------------
Write-Ascii (P 'part.dfm') @'
object src1: TLazySrc
  object part1: TPartF
  end
end
'@
$fr = Book 'part.rules' "$Hdr`n#link Hue <- Shade`n#convert LibLazy.TPartF -> LibLazy.TPartT, LibLazy`n#link Hue <- Shade`n"
$o = (& $Exe convert-reemit --from-block (P 'part.dfm') --rules $fr --from LibLazy.TLazySrc --to LibLazy.TLazyDst --db $db 2>$null) -join "`n"
$rj = Json $o
$dfm = if ($rj) { [string]$rj.dfm } else { '' }
$pm = [regex]::Match($dfm, '(?s)  object part1: TPartT\r?\n(.*?)  end\r?\n')
Check 'F1 the parent carries its own absent default (Hue = 3, at the parent''s indent)' ($dfm -match '(?m)^  Hue = 3\r?$') $o
Check 'F2 the owned part gets NO Hue -- not answered from the parent''s class' ($pm.Success -and -not ($pm.Groups[1].Value -match 'Hue')) $o

Write-Ascii (P 'h.dfm') @'
object src1: TLazySrc
  Shade = 7
  P1.P2.Leaf2 = 9
  object part1: TPartF
    Shade = 4
  end
end
'@
$hr = Book 'h.rules' "$Hdr`n#link Hue <- Shade`n#link Deep <- P1.P2.Leaf2`n#link Title <- P1.P2.P3.Leaf3`n#convert LibLazy.TPartF -> LibLazy.TPartT, LibLazy`n#link Hue <- Shade`n"
$o = (& $Exe convert-reemit --from-block (P 'h.dfm') --rules $hr --from LibLazy.TLazySrc --to LibLazy.TLazyDst --db $db 2>$null) -join "`n"
$hj = Json $o
# Captured from the 14396852 engine (depth-6 trees) on this block and book.
$golden = "object src1: TLazyDst`r`n  Hue = 7`r`n  Deep = 9`r`n  object part1: TPartT`r`n    Hue = 4`r`n  end`r`n  Title = 11`r`nend"
$got = if ($hj) { ([string]$hj.dfm).TrimEnd() } else { '<no json>' }
Check 'H1 convert-reemit output is byte-identical to the old engine''s' ($got -ceq $golden) ("got: " + ($got -replace "`r`n", '|'))

# ---- R: the real BDE book --------------------------------------------------
if ($RealBook) {
  Write-Host ''
  Write-Host 'Real-book arm' -ForegroundColor Cyan
  if (-not ($LibDb -and (Test-Path $LibDb))) {
    Write-Host '  [SKIP] -LibDb not given or absent' -ForegroundColor Yellow
  } else {
    $real = P 'real'
    New-Item -ItemType Directory $real | Out-Null
    Write-Ascii (Join-Path $real 'QryUnit.pas') @'
unit QryUnit;

interface

uses
  System.Classes, Data.DB, Bde.DBTables;

type
  TdmQry = class(TDataModule)
    qry1: TQuery;
  end;

var
  dmQry: TdmQry;

implementation

{$R *.dfm}

end.
'@
    Write-Ascii (Join-Path $real 'QryUnit.dfm') @'
object dmQry: TdmQry
  object qry1: TQuery
    DatabaseName = 'MAIN'
    SQL.Strings = (
      'select 1 from rdb$database')
  end
end
'@
    $qdb = Join-Path $real 'qry.sqlite'
    & $Exe index $real --db $qdb 2>&1 | Out-Null
    $dbArgs = @('--db', $qdb)
    if ($DmDb -and (Test-Path $DmDb)) { $dbArgs += @('--db', $DmDb) }
    $dbArgs += @('--db', $LibDb)
    $BookText = [IO.File]::ReadAllText((Resolve-Path $Book).Path)

    # The book's #links that ruling R8 rejects: each FromPath hops through a
    # property PROTECTED on the BDE source class (Data.DB.TDataSet declares
    # FieldOptions and Constraints protected; TQuery republishes Constraints,
    # TTable/TStoredProc publish neither), so no .dfm can stream it. The editor's
    # Auto-Match filtered only the LEAF by visibility, which is how they got in.
    $R8Rejected = @(274, 275, 276, 277, 374, 375, 376, 377, 478, 479, 480, 481, 482, 483, 484, 485)
    function R8Stripped([string[]]$Src, [int]$FirstLine) {
      $out = New-Object System.Collections.Generic.List[string]
      for ($k = 0; $k -lt $Src.Count; $k++) {
        $out.Add($(if ($R8Rejected -contains ($FirstLine + $k)) { '// R8-rejected: ' + $Src[$k] } else { $Src[$k] }))
      }
      return ,$out.ToArray()
    }

    # R1: the book's TQuery block alone, one --from/--to pair.
    $lines = $BookText -split "`r?`n"
    $start = [Array]::FindIndex($lines, [Predicate[string]]{ param($x) $x -match '^#convert Bde\.DBTables\.TQuery ' })
    $end = $start + 1
    while ($end -lt $lines.Count -and $lines[$end] -notmatch '^#convert ') { $end++ }
    $blk = $lines[$start..($end - 1)]
    $qb = Join-Path $real 'tquery-block.rules'
    Write-Ascii $qb ($blk -join "`n")
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $o = (& $Exe convert-validate --rules $qb --from Bde.DBTables.TQuery --to FireDAC.Comp.Client.TFDQuery @dbArgs 2>&1) -join "`n"
    $code = $LASTEXITCODE; $sw.Stop()
    $el = ErrLines $o
    Write-Host ("  convert-validate (TQuery block, {0} lines): {1:N1} s, {2} error(s)" -f $blk.Count, $sw.Elapsed.TotalSeconds, $el.Count)
    $wl = @($o -split "`r?`n" | Where-Object { $_ -match '^line \d+: warning: FieldOptions\.\S+: FieldOptions is protected in Data\.DB\.TDataSet; never applied unless a descendant class changes its visibility$' })
    Write-Host ("  ... {0} unreachable warning(s)" -f $wl.Count)
    Check 'R1a TQuery block (unedited): < 30 s; exit 0, NO errors, exactly 4 unreachable warnings on the FieldOptions.* links (protected in TDataSet; owner ruling T2h)' `
      (($code -eq 0) -and ($sw.Elapsed.TotalSeconds -lt 30) -and ($el.Count -eq 0) -and ($wl.Count -eq 4) -and `
       (@($o -split "`r?`n" | Where-Object { $_ -match 'warning: .* never applied unless' }).Count -eq 4)) $o
    $qb2 = Join-Path $real 'tquery-block-r8.rules'
    Write-Ascii $qb2 ((R8Stripped $blk ($start + 1)) -join "`n")
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $o = (& $Exe convert-validate --rules $qb2 --from Bde.DBTables.TQuery --to FireDAC.Comp.Client.TFDQuery @dbArgs 2>&1) -join "`n"
    $code = $LASTEXITCODE; $sw.Stop()
    Write-Host ("  convert-validate (TQuery block, R8-rejected lines commented out): {0:N1} s" -f $sw.Elapsed.TotalSeconds)
    Check 'R1b TQuery block without the R8-rejected links: exit 0 in < 30 s' (($code -eq 0) -and ($sw.Elapsed.TotalSeconds -lt 30)) $o

    # R2: the whole book, convert-apply dry run.
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $o = (& $Exe convert-apply --unit (Join-Path $real 'QryUnit.pas') --rules (Resolve-Path $Book).Path @dbArgs --format json 2>$null) -join "`n"
    $code = $LASTEXITCODE; $sw.Stop()
    $aj = Json $o
    $unrLines = @($aj.unreachable | ForEach-Object { [int]$_.line } | Sort-Object -Unique)
    Write-Host ("  convert-apply dry run (whole book, every block validated): {0:N1} s, classes_built={1}, rule errors={2}, unreachable on lines {3}" -f `
      $sw.Elapsed.TotalSeconds, $(if ($aj) { $aj.classes_built } else { '?' }), @($aj.rule_errors).Count, ($unrLines -join ','))
    Check 'R2a whole book (unedited): < 60 s; exit 0, ok=true, qry1 converted, 0 rule errors, exactly 16 unreachable warnings on the R8 lines' `
      (($code -eq 0) -and ($null -ne $aj) -and $aj.ok -and ($sw.Elapsed.TotalSeconds -lt 60) -and (@($aj.rule_errors).Count -eq 0) -and `
       (@($aj.unreachable).Count -eq 16) -and ((Compare-Object $unrLines $R8Rejected | Measure-Object).Count -eq 0) -and `
       (@($aj.unreachable | Where-Object { $_.reason -ne 'unreachable' -or $_.visibility -ne 'protected' }).Count -eq 0) -and `
       (@($aj.warnings | Where-Object { $_ -match '^line \d+: warning: .* never applied unless' }).Count -eq 16) -and `
       (@($aj.converted | Where-Object { $_ -match '^qry1: TQuery -> TFDQuery' }).Count -eq 1)) $o
    $bk2 = Join-Path $real 'BDE-to-FireDAC-r8.rules'
    Write-Ascii $bk2 ((R8Stripped $lines 1) -join "`n")
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $o = (& $Exe convert-apply --unit (Join-Path $real 'QryUnit.pas') --rules $bk2 @dbArgs --format json 2>$null) -join "`n"
    $code = $LASTEXITCODE; $sw.Stop()
    $aj = Json $o
    Write-Host ("  convert-apply dry run (whole book, R8-rejected links commented out): {0:N1} s, classes_built={1}" -f `
      $sw.Elapsed.TotalSeconds, $(if ($aj) { $aj.classes_built } else { '?' }))
    Check 'R2b whole book without the R8-rejected links: exit 0, ok=true, qry1 converted, < 60 s' `
      (($code -eq 0) -and ($null -ne $aj) -and $aj.ok -and (@($aj.converted | Where-Object { $_ -match '^qry1: TQuery -> TFDQuery' }).Count -eq 1) -and `
       ($sw.Elapsed.TotalSeconds -lt 60)) $o
    # R3: per-path equivalence with the old engine's trees.
    if ($OldDumpDir -and (Test-Path $OldDumpDir)) {
      # New engine's answers: every path the whole-book validation did NOT name.
      $txt = (& $Exe convert-apply --unit (Join-Path $real 'QryUnit.pas') --rules (Resolve-Path $Book).Path @dbArgs 2>&1) -join "`n"
      $newMiss = @{}
      foreach ($m in [regex]::Matches($txt, '(?m)^\s*line (\d+): (?:link|default|mapping \S+) (?:#when path|target path|ToPath|FromPath) not found in --(from|to) tree: (.+?)(?: \(#convert line \d+:.*\))?\s*$')) {
        $newMiss["$($m.Groups[1].Value)|$($m.Groups[2].Value)|$($m.Groups[3].Value)"] = $true
      }
      # T2h: an unreachable path is a WARNING now, and is never applied. The
      # warning names no side (every R8 line in this book spells the SAME path
      # on both sides), so a warned (line, path) is judged as a group below: it
      # agrees when the old tree fails R8 on at least one of its sides.
      $warned = @{}
      foreach ($m in [regex]::Matches($txt, '(?m)^\s*line (\d+): warning: (\S+): \S+ is \S+(?: \S+)? in \S+; never applied unless')) {
        $warned["$($m.Groups[1].Value)|$($m.Groups[2].Value)"] = $true
      }
      $warnGroups = @{}
      $trees = @{}
      function OldTree([string]$q) {
        if ($trees.ContainsKey($q)) { return $trees[$q] }
        $f = @((Join-Path $OldDumpDir "$q.d6.json"), (Join-Path $OldDumpDir "$q.d4.json"), (Join-Path $OldDumpDir "$q.d2.json")) | Where-Object { (Test-Path $_) -and ((Get-Item $_).Length -gt 0) } | Select-Object -First 1
        $map = $null
        if ($f) {
          $js = Get-Content -Raw $f | ConvertFrom-Json
          $map = @{}
          foreach ($n in $js.properties) { if (-not $map.ContainsKey($n.path.ToLower())) { $map[$n.path.ToLower()] = $n } }
        }
        $trees[$q] = $map
        return $map
      }
      # Old answer under R8, private excluded on every hop.
      function OldFound($map, [string]$path) {
        $segs = $path.Split('.')
        for ($k = 1; $k -le $segs.Count; $k++) {
          $n = $map[(($segs[0..($k - 1)]) -join '.').ToLower()]
          if ($null -eq $n) { return $false }
          if ($n.visibility -eq 'private') { return $false }
          if ($n.member_kind -ne 'property') { return $false }
          if ($k -eq $segs.Count) { return ($n.visibility -eq 'published') }
          if (-not (($n.visibility -eq 'published') -or (($n.visibility -eq 'public') -and $n.is_class_typed))) { return $false }
        }
        return $false
      }
      function OldFoundRaw($map, [string]$path) {
        $segs = $path.Split('.')
        for ($k = 1; $k -le $segs.Count; $k++) {
          $n = $map[(($segs[0..($k - 1)]) -join '.').ToLower()]
          if (($null -eq $n) -or ($n.visibility -eq 'private')) { return $false }
        }
        return $true
      }
      # Parse the book: blocks, and each checked (line, side, path, class).
      $blockFrom = @{}; $blockTo = @{}; $block = 0; $applies = @{}; $lineBlock = @{}
      for ($i = 0; $i -lt $lines.Count; $i++) {
        $L = $lines[$i].Trim()
        if ($L -match '^#convert\s+(\S+)\s*->\s*([^,\s]+)') { $block++; $blockFrom[$block] = $Matches[1]; $blockTo[$block] = $Matches[2] }
        if ($L -match '^#apply\s+(\S+)' -and $block -gt 0) { if (-not $applies.ContainsKey($Matches[1])) { $applies[$Matches[1]] = @() }; $applies[$Matches[1]] += $block }
        $lineBlock[$i + 1] = $block
      }
      $checks = New-Object System.Collections.Generic.List[object]
      for ($i = 0; $i -lt $lines.Count; $i++) {
        $L = $lines[$i].Trim(); $ln = $i + 1; $b = $lineBlock[$ln]
        if ($L -match '^#link\s+(\S+)\s*<-\s*(\S+)') {
          if ($Matches[1] -ne '???') { $checks.Add(@($ln, 'to', $Matches[1], @($b))) }
          if ($Matches[2] -ne '???') { $checks.Add(@($ln, 'from', $Matches[2], @($b))) }
        } elseif ($L -match '^#default\s+(\S+)\s*=') {
          $checks.Add(@($ln, 'to', $Matches[1], @($b)))
        } elseif ($L -match '^#mapping\s+(\S+)\s+#(when|else)\b(.*)$') {
          $name = $Matches[1]; $rest = $Matches[3]
          $bs = if ($applies.ContainsKey($name)) { $applies[$name] } elseif ($b -gt 0) { @($b) } else { @() }
          if ($Matches[2] -eq 'when' -and $rest -match '^\s*(\S+)\s*=') { $checks.Add(@($ln, 'from', $Matches[1], $bs)) }
          if ($rest -match '->\s*(.+)$') { foreach ($set in $Matches[1].Split(',')) { if ($set.Trim() -match '^(\S+)') { $checks.Add(@($ln, 'to', $Matches[1], $bs)) } } }
        }
      }
      $agree = 0; $disagree = @(); $rawDiff = 0; $noDump = @{}
      foreach ($c in $checks) {
        foreach ($bb in $c[3]) {
          $q = if ($c[1] -eq 'from') { $blockFrom[$bb] } else { $blockTo[$bb] }
          $map = OldTree $q
          if ($null -eq $map) { $noDump[$q] = $true; continue }
          $old = OldFound $map $c[2]
          if ((OldFoundRaw $map $c[2]) -ne $old) { $rawDiff++ }
          $wk = "$($c[0])|$($c[2])"
          if ($warned.ContainsKey($wk)) {
            if (-not $warnGroups.ContainsKey($wk)) { $warnGroups[$wk] = @() }
            $warnGroups[$wk] += $old
            continue
          }
          $new = -not $newMiss.ContainsKey("$($c[0])|$($c[1])|$($c[2])")
          if ($old -eq $new) { $agree++ } else { $disagree += "line $($c[0]) $($c[1]) $($c[2]) in $q : old=$old new=$new" }
        }
      }
      foreach ($wk in $warnGroups.Keys) {
        if (@($warnGroups[$wk] | Where-Object { -not $_ }).Count -gt 0) { $agree++ } else { $disagree += "warned $wk but the old tree passes R8 on every side" }
      }
      Write-Host ("  equivalence: {0} warned (line, path) group(s)" -f $warnGroups.Count)
      Write-Host ("  equivalence: {0} path check(s) agree, {1} disagree; {2} differ from the plain minus-private tree only by ruling R8; no dump for: {3}" -f `
        $agree, $disagree.Count, $rawDiff, (($noDump.Keys | Sort-Object) -join ', '))
      Check 'R3 every book path: new found/not-found == old depth-6/4/2 tree minus private, under R8' `
        (($disagree.Count -eq 0) -and ($agree -gt 0) -and ($noDump.Count -eq 0)) ($disagree -join ' | ')
    } else {
      Write-Host '  [SKIP] R3 equivalence: -OldDumpDir not given' -ForegroundColor Yellow
    }
  }
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # This run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("$env:TEMP\drag-lint-convert-lazy-paths-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
