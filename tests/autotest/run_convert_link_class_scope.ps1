<#
  run_convert_link_class_scope.ps1 -- a #convert block's From / To class, the
  class every #link / #default / #ignore path of that block is checked against,
  is resolved through the SAME scope as pas_uses[] (ResolveClassInScope), never
  by "first class of that name wins".

  THE DEFECT (after 1.28.2): TConvertTreeCache.Lookup resolved a bare #convert
  From/To by the first skClass of that name across the --db stores. With
  FMX.StdCtrls.TLabel indexed before Vcl.StdCtrls.TLabel, a VCL unit's
  '#link Wrap <- WordWrap' was "not found" and an FMX-only path was accepted; a
  bare To type landed on a NESTED class of the same name (LibNest.TNestHost.TSolo,
  "ToPath not found").

  THE CONTRACT:
    * a QUALIFIED name resolves to exactly that class;
    * a bare name resolves in the converted unit's scope (the unit, its last
      uses entry declaring it, the book's own qualification, a lone unit-level
      declarer); a NESTED class is never a declarer;
    * a bare name still ambiguous REFUSES -- convert-apply refuses the unit,
      convert-validate / convert-reemit refuse the run -- naming the
      candidates and asking for the #convert line (or --from/--to) to be
      qualified. Nothing is validated against a guess.

  Fixture written fresh under a $PID scratch folder; scratch --db files there.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_link_class_scope_$PID"
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
New-Item -ItemType Directory (P 'lib'), (P 'app') -Force | Out-Null

# ---- library: two TLabels with DIFFERENT published surfaces, a nested TLabel
# and a nested TSolo, each indexed BEFORE the unit-level class a guess must not
# replace (alphabetical file order: FMX < LibNest < LibSolo < Vcl) ------------
W 'lib\FMX.StdCtrls.pas' @'
unit FMX.StdCtrls;

interface

type
  TLabel = class
  private
    FFmxOnly: Boolean;
  published
    property FmxOnly: Boolean read FFmxOnly write FFmxOnly;
  end;

implementation

end.
'@
W 'lib\LibNest.pas' @'
unit LibNest;

interface

type
  TNestHost = class
  public
    type
      TLabel = class
      private
        FNestOnly: Boolean;
      published
        property NestOnly: Boolean read FNestOnly write FNestOnly;
      end;
      TSolo = class
      private
        FNestFlag: Boolean;
      published
        property NestFlag: Boolean read FNestFlag write FNestFlag;
      end;
  end;

implementation

end.
'@
W 'lib\LibSolo.pas' @'
unit LibSolo;

interface

type
  TSolo = class
  private
    FWrap: Boolean;
  published
    property Wrap: Boolean read FWrap write FWrap;
  end;

implementation

end.
'@
W 'lib\Vcl.StdCtrls.pas' @'
unit Vcl.StdCtrls;

interface

type
  TTextLayout = (tlTop, tlCenter, tlBottom);

  TLabel = class
  private
    FLayout: TTextLayout;
    FWordWrap: Boolean;
  published
    property Layout: TTextLayout read FLayout write FLayout;
    property WordWrap: Boolean read FWordWrap write FWordWrap;
  end;

implementation

end.
'@

# ---- app: one form per uses shape ------------------------------------------
function Form([string]$Name, [string]$Uses) {
  W "app\$Name.pas" ("unit $Name;`n`ninterface`n`n$Uses`n`ntype`n  T$Name = class`n    Label1: TLabel;`n  end;`n`nimplementation`n`n{`$R *.dfm}`n`nend.`n")
  W "app\$Name.dfm" "object ${Name}: T$Name`n  object Label1: TLabel`n  end`nend`n"
}
Form 'UVcl'  "uses`n  Vcl.StdCtrls;"
Form 'UFmx'  "uses`n  FMX.StdCtrls;"
Form 'UNone' "uses`n  LibSolo;"
W 'app\P.dpr' "program P;`n`nuses`n  UVcl, UFmx, UNone;`n`nbegin`nend.`n"

W 'bare_vcl.rules'  "#convert TLabel -> TSolo`n#link Wrap <- WordWrap`n"
W 'bare_fmx.rules'  "#convert TLabel -> TSolo`n#link Wrap <- FmxOnly`n"
W 'q_fmx_ok.rules'  "#convert FMX.StdCtrls.TLabel -> LibSolo.TSolo`n#link Wrap <- FmxOnly`n"
W 'q_fmx_bad.rules' "#convert FMX.StdCtrls.TLabel -> LibSolo.TSolo`n#link Wrap <- WordWrap`n"
W 'q_vcl.rules'     "#convert Vcl.StdCtrls.TLabel -> LibSolo.TSolo`n#link Wrap <- WordWrap`n"
W 'nest.rules'      "#convert Vcl.StdCtrls.TLabel -> TSolo`n#link NestFlag <- WordWrap`n"
W 'q_vcl_bad.rules' "#convert Vcl.StdCtrls.TLabel -> LibSolo.TSolo`n#link Wrap <- FmxOnly`n"

& $Exe index (P 'lib') --db (P 'lib.sqlite') 2>&1 | Out-Null
& $Exe index --project (P 'app\P.dpr') --db (P 'app.sqlite') 2>&1 | Out-Null
$c0 = (& $Exe sql --db (P 'lib.sqlite') --query "select qualified_name from symbols where kind = 'class' and name in ('TLabel','TSolo') order by id" 2>$null) -join "`n"
Check 'P0 premise: FMX.StdCtrls.TLabel and the NESTED TLabel / TSolo are indexed before the classes a guess must not replace' `
  ($c0 -match '(?s)FMX\.StdCtrls\.TLabel.*LibNest\.TNestHost\.TLabel.*LibNest\.TNestHost\.TSolo.*LibSolo\.TSolo.*Vcl\.StdCtrls\.TLabel') $c0

function Apply([string]$Unit, [string]$Rules) {
  $o = (& $Exe convert-apply --unit (P "app\$Unit.pas") --rules (P $Rules) --db (P 'app.sqlite') --db (P 'lib.sqlite') 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function ApplyJ([string]$Unit, [string]$Rules) {
  $o = (& $Exe convert-apply --unit (P "app\$Unit.pas") --rules (P $Rules) --db (P 'app.sqlite') --db (P 'lib.sqlite') --format json 2>$null) -join "`n"
  $r = [pscustomobject]@{ Code = $LASTEXITCODE; J = $null; Out = $o }; try { $r.J = $o.Substring($o.IndexOf('{')) | ConvertFrom-Json } catch {}
  return $r
}
function Validate([string]$Rules, [string]$From, [string]$To) {
  $o = (& $Exe convert-validate --rules (P $Rules) --from $From --to $To --db (P 'lib.sqlite') 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
$amb = 'FMX\.StdCtrls, Vcl\.StdCtrls'

# ---- A: bare #convert in a unit that uses Vcl.StdCtrls ---------------------
$r = Apply 'UVcl' 'bare_vcl.rules'
Check 'A1 bare #convert TLabel -> TSolo in a Vcl.StdCtrls unit: the VCL-only path WordWrap validates (and the bare To is LibSolo.TSolo, not the nested one)' `
  (($r.Code -eq 0) -and -not ($r.Out -match 'not found|REFUSED|failed validation')) $r.Out
$r = Apply 'UVcl' 'bare_fmx.rules'
Check 'A2 ... and the FMX-only path FmxOnly is REJECTED there' `
  (($r.Code -eq 1) -and ($r.Out -match 'failed validation') -and ($r.Out -match '(?m)line 2: .*FmxOnly')) $r.Out
$r = Apply 'UFmx' 'bare_fmx.rules'
Check 'A3 positive control: the same bare book in an FMX.StdCtrls unit validates FmxOnly' `
  (($r.Code -eq 0) -and -not ($r.Out -match 'not found|REFUSED|failed validation')) $r.Out

# ---- Q: a qualified #convert is taken as written, whatever the scope -------
$r = Apply 'UVcl' 'q_fmx_ok.rules'
Check 'Q1 #convert FMX.StdCtrls.TLabel (in a Vcl unit): FmxOnly validates' `
  (($r.Code -eq 0) -and -not ($r.Out -match 'not found|REFUSED|failed validation')) $r.Out
$r = Apply 'UVcl' 'q_fmx_bad.rules'
Check 'Q2 ... and the VCL-only WordWrap is REJECTED' `
  (($r.Code -eq 1) -and ($r.Out -match 'failed validation') -and ($r.Out -match '(?m)line 2: .*WordWrap')) $r.Out
$r = Validate 'q_fmx_ok.rules' 'FMX.StdCtrls.TLabel' 'LibSolo.TSolo'
Check 'Q3 convert-validate --from FMX.StdCtrls.TLabel: FmxOnly validates (OK)' (($r.Code -eq 0) -and ($r.Out -match '(?m)^OK\s*$')) $r.Out
$r = Validate 'q_fmx_bad.rules' 'FMX.StdCtrls.TLabel' 'LibSolo.TSolo'
Check 'Q4 convert-validate --from FMX.StdCtrls.TLabel: WordWrap rejected' (($r.Code -eq 1) -and ($r.Out -match '(?m)^line 2: .*WordWrap')) $r.Out

# ---- G: genuinely ambiguous bare name -> REFUSED, candidates named ---------
$r = Apply 'UNone' 'bare_vcl.rules'
Check 'G1 convert-apply, a unit whose scope declares no TLabel, bare book: REFUSED naming both candidates, asking to qualify the #convert line' `
  (($r.Code -eq 1) -and ($r.Out -match ('(?m)^REFUSED: .*TLabel \(line 1\) is ambiguous.*' + $amb + '.*qualify the #convert line'))) $r.Out
$j = ApplyJ 'UNone' 'bare_vcl.rules'
Check 'G2 ... JSON: ok=false, refused=true, the reason names the candidates' `
  (($j.Code -eq 1) -and ($null -ne $j.J) -and ($j.J.ok -eq $false) -and ($j.J.refused -eq $true) -and ($j.J.reason -match $amb)) $j.Out
$r = Validate 'bare_vcl.rules' 'TLabel' 'TSolo'
Check 'G3 convert-validate --from TLabel (no unit, bare book): refuses, exit 1, both candidates named, asks to qualify; never OK' `
  (($r.Code -eq 1) -and ($r.Out -match ('(?m)^ERROR: --from TLabel is ambiguous.*' + $amb + '.*qualify')) -and -not ($r.Out -match '(?m)^OK')) $r.Out
$r = Validate 'q_vcl.rules' 'TLabel' 'TSolo'
Check 'G4 convert-validate --from TLabel with a book that says #convert Vcl.StdCtrls.TLabel: the book''s qualification settles it -- OK' `
  (($r.Code -eq 0) -and ($r.Out -match '(?m)^OK\s*$')) $r.Out
$r = Validate 'q_vcl_bad.rules' 'TLabel' 'TSolo'
Check 'G4b ... and it is a REAL check, not a parse-only pass: the FMX-only FmxOnly is rejected under the same --from TLabel' `
  (($r.Code -eq 1) -and ($r.Out -match '(?m)^line 2: .*FmxOnly')) $r.Out
W 'blk.dfm' "object Label1: TLabel`n  WordWrap = True`nend`n"
$o = (& $Exe convert-reemit --from-block (P 'blk.dfm') --rules (P 'bare_vcl.rules') --from TLabel --to TSolo --db (P 'lib.sqlite') 2>&1) -join "`n"
Check 'G5 convert-reemit --from TLabel (bare, ambiguous): refuses, exit 1, candidates named' `
  (($LASTEXITCODE -eq 1) -and ($o -match ('(?m)^ERROR: --from TLabel is ambiguous.*' + $amb))) $o

# ---- N: a nested class is never a declarer ---------------------------------
$r = Apply 'UVcl' 'nest.rules'
Check 'N1 bare To TSolo is LibSolo.TSolo, never LibNest.TNestHost.TSolo: the nested-only NestFlag is REJECTED' `
  (($r.Code -eq 1) -and ($r.Out -match '(?m)line 2: .*NestFlag')) $r.Out
$r = Validate 'q_vcl.rules' 'Vcl.StdCtrls.TLabel' 'TSolo'
Check 'N2 convert-validate --to TSolo (bare): the lone UNIT-LEVEL TSolo, Wrap validates -- OK' `
  (($r.Code -eq 0) -and ($r.Out -match '(?m)^OK\s*$')) $r.Out
$r = Validate 'nest.rules' 'Vcl.StdCtrls.TLabel' 'TSolo'
Check 'N2b ... a REAL check: the nested TSolo''s NestFlag is rejected under --to TSolo' `
  (($r.Code -eq 1) -and ($r.Out -match '(?m)^line 2: .*NestFlag')) $r.Out

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
