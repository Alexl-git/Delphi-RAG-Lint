<#
  run_convert_apply_inherited_retype.ps1 -- C8 engine items N2 and N2a (spec
  docs\superpowers\specs\2026-10-05-c8-inherited-instances-design.md), 1.26.0.

  BEFORE (1.22.0 .. 1.25.0, N1): an inherited / inline .dfm object of a From
  type was SKIPPED even when its declaring ancestor already had the block's To
  type (ancestor_state `converted`), so the descendant kept streaming the old
  class and its code kept the old member names -- it no longer loaded or
  compiled against its converted ancestor.

  THE CONTRACT this guard pins:
    N2  an inherited / inline instance whose declaring ancestor ALREADY has the
        To type is RETYPED: `inherited X: TFrom` -> `inherited X: TTo` (the
        keyword kept), nested blocks and inline-frame children included; the
        properties the block overrides convert per the book (#link renames);
        an ABSENT property means INHERITED, so nothing is resolved from its
        declared default and no #default is written into the block; code
        access sites on X are rewritten exactly as for own instances.
    N2  apply/1 inherited[] gains the key `action`: `retyped` for these,
        `skipped` for every other state (unconverted / mismatched / outside),
        which stay byte-unchanged. The six existing keys keep their meaning.
        A retyped instance is one converted[] line and an items[] mirror of
        kind inherited-instance-retyped; it is no warning.
    N2a every code access on a field a CONVERTED ancestor declares (bound by
        the resolver to that field), several levels up, is rewritten -- also
        when the descendant .dfm never re-opens the component. It is reported
        in inherited[] with action `code`, its line the first code reference.
    uses the To type's unit is added to the descendant (section rule; an own
        interface field still puts it in the interface).
    --only filters retyped and code entries by name; a code-only name counts
        as matched (only_matched[]).
    batch: two descendants in one run are both retyped.
    info --json: capabilities.inherited_retype is the JSON literal true.
    Positive control: an own instance in the same unit converts exactly as
        before (its absent defaulted property IS carried, #default IS written).
    The converted descendants compile with dcc64 against the converted
        ancestors.

  Fixture written fresh under a $PID scratch folder and indexed into a scratch
  --db there. Nothing shared is touched. Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_inh_retype_$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [switch]$NoCompile
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
function Text([string]$n) { return [IO.File]::ReadAllText((P $n)) }

# ---- library types ---------------------------------------------------------
Write-Ascii (P 'LibA.pas') @'
unit LibA;

interface

uses
  System.Classes;

type
  TSrcA = class(TComponent)
  private
    FCaption: string;
    FHint: string;
    FSize: Integer;
  published
    property Caption: string read FCaption write FCaption;
    property Hint: string read FHint write FHint;
    property Size: Integer read FSize write FSize default 3;
  end;

  TBox = class(TComponent)
  end;

implementation

end.
'@

Write-Ascii (P 'LibB.pas') @'
unit LibB;

interface

uses
  System.Classes;

type
  TDstB = class(TComponent)
  private
    FTitle: string;
    FHint: string;
    FSize: Integer;
    FColor: Integer;
  published
    property Title: string read FTitle write FTitle;
    property Hint: string read FHint write FHint;
    property Size: Integer read FSize write FSize;
    property Color: Integer read FColor write FColor;
  end;

implementation

end.
'@

# ---- the CONVERTED ancestor chain: RBase declares, RMid adds nothing ---------
Write-Ascii (P 'RBase.pas') @'
unit RBase;

interface

uses
  System.Classes, Vcl.Forms, LibA, LibB;

type
  TRBase = class(TForm)
    rbtn: TDstB;
    rpnl: TBox;
    rnest: TDstB;
    rcode: TDstB;
    ubtn: TSrcA;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'RBase.dfm') @'
object RBase: TRBase
  object rbtn: TDstB
    Title = 'B'
    Size = 7
  end
  object rpnl: TBox
    object rnest: TDstB
      Title = 'N'
    end
  end
  object rcode: TDstB
    Title = 'C'
  end
  object ubtn: TSrcA
    Caption = 'U'
  end
end
'@

Write-Ascii (P 'RMid.pas') @'
unit RMid;

interface

uses
  System.Classes, Vcl.Forms, RBase;

type
  TRMid = class(TRBase)
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'RMid.dfm') @'
inherited RMid: TRMid
end
'@

Write-Ascii (P 'RFrame.pas') @'
unit RFrame;

interface

uses
  System.Classes, Vcl.Forms, LibB;

type
  TRFrame = class(TFrame)
    fb: TDstB;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'RFrame.dfm') @'
object RFrame: TRFrame
  object fb: TDstB
    Title = 'F'
  end
end
'@

# ---- the descendant: two levels below RBase, with its own instance ----------
Write-Ascii (P 'RChild.pas') @'
unit RChild;

interface

uses
  System.Classes, Vcl.Forms, LibA, RMid, RFrame;

type
  TRChild = class(TRMid)
    own: TSrcA;
    frm: TRFrame;
    procedure Touch;
  end;

implementation

{$R *.dfm}

procedure TRChild.Touch;
begin
  rbtn.Caption := 'x';
  rcode.Caption := 'y';
  own.Caption := 'z';
  ubtn.Caption := 'u';
  rnest.Hint := rbtn.Caption;
end;

end.
'@
Write-Ascii (P 'RChild.dfm') @'
inherited RChild: TRChild
  inherited rbtn: TSrcA
    Caption = 'child'
    Hint = 'h'
  end
  inherited rpnl: TBox
    inherited rnest: TSrcA
      Caption = 'n2'
    end
  end
  inherited ubtn: TSrcA
    Caption = 'u2'
  end
  object own: TSrcA
    Caption = 'own'
  end
  inline frm: TRFrame
    inherited fb: TSrcA
      Caption = 'f2'
    end
  end
end
'@

# ---- a CODE-ONLY descendant: no .dfm re-open, no own instance (N2a) ---------
Write-Ascii (P 'RCode.pas') @'
unit RCode;

interface

uses
  System.Classes, Vcl.Forms, RMid;

type
  TRCode = class(TRMid)
    procedure Touch;
  end;

implementation

{$R *.dfm}

procedure TRCode.Touch;
var
  S: string;
begin
  S := rcode.Caption;
  rcode.Caption := S + '!';
end;

end.
'@
Write-Ascii (P 'RCode.dfm') @'
inherited RCode: TRCode
end
'@

# a code-only reference whose receiver is a LOCAL of that name: not the field
Write-Ascii (P 'RShadow.pas') @'
unit RShadow;

interface

uses
  System.Classes, Vcl.Forms, LibA, RMid;

type
  TRShadow = class(TRMid)
    procedure Touch;
  end;

implementation

{$R *.dfm}

procedure TRShadow.Touch;
var
  rcode: TSrcA;
begin
  rcode := nil;
  if rcode <> nil then rcode.Caption := 'local';
end;

end.
'@
Write-Ascii (P 'RShadow.dfm') @'
inherited RShadow: TRShadow
end
'@

Write-Ascii (P 'retype.rules') @'
#convert LibA.TSrcA -> LibB.TDstB, LibB
#link Title <- Caption
#link Hint <- Hint
#link Size <- Size
#default Color = 5
'@

$db = P 'fx.sqlite'
$idx = & $Exe index $WorkDir --db $db 2>&1
Check 'V the fixture index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE; $($idx -join ' | ')"

function ApplyTo([string[]]$Units, [string]$Rules, [string[]]$Extra = @()) {
  $a = @('convert-apply')
  foreach ($u in $Units) { $a += @('--unit', (P $u)) }
  $a += @('--rules', (P $Rules), '--db', $db) + $Extra
  $o = (& $Exe @a 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function Json([string]$s) {
  $a = $s.IndexOf('{'); $b = $s.LastIndexOf('}')
  if ($a -lt 0 -or $b -le $a) { return $null }
  try { return ($s.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch { return $null }
}
function Inh($j, [string]$Name) { return @($j.inherited | Where-Object { $_.name -eq $Name }) }
function Block([string]$Text, [string]$Header) {
  # the block text from its header line through its matching end (by indent)
  $ls = $Text -split "`r`n"
  for ($i = 0; $i -lt $ls.Count; $i++) {
    if ($ls[$i].Trim() -eq $Header) {
      $ind = $ls[$i].Length - $ls[$i].TrimStart().Length
      $k = $i + 1
      while ($k -lt $ls.Count -and -not (($ls[$k].Trim() -eq 'end') -and (($ls[$k].Length - $ls[$k].TrimStart().Length) -eq $ind))) { $k++ }
      return ($ls[$i..$k] -join "`n")
    }
  }
  return ''
}

# ---- dry run, JSON ------------------------------------------------------------
$r = ApplyTo @('RChild.pas') 'retype.rules' @('--format', 'json')
$j = Json $r.Out
Check 'A1 RChild dry run: exit 0, ok' (($r.Code -eq 0) -and ($null -ne $j) -and $j.ok) $r.Out
$keys = if ($j -and @($j.inherited).Count -gt 0) { (@($j.inherited)[0].PSObject.Properties.Name) -join ',' } else { '' }
Check 'A2 inherited[] keys: the six N1 keys, then action' ($keys -eq 'name,type,line,ancestor_unit,ancestor_state,reason,action') $keys
$b = Inh $j 'rbtn'
Check 'A3 rbtn: ancestor RBase (two levels up), converted, action retyped' `
  (($b.Count -eq 1) -and ($b[0].ancestor_unit -eq 'RBase') -and ($b[0].ancestor_state -eq 'converted') -and ($b[0].action -eq 'retyped') -and ($b[0].type -eq 'TSrcA')) ($b | ConvertTo-Json -Compress)
$n = Inh $j 'rnest'
Check 'A4 nested rnest (inside inherited rpnl): retyped' (($n.Count -eq 1) -and ($n[0].action -eq 'retyped')) ($n | ConvertTo-Json -Compress)
$f = Inh $j 'fb'
Check 'A5 inline frame child fb: ancestor RFrame, retyped' (($f.Count -eq 1) -and ($f[0].ancestor_unit -eq 'RFrame') -and ($f[0].action -eq 'retyped')) ($f | ConvertTo-Json -Compress)
$u = Inh $j 'ubtn'
Check 'A6 ubtn (ancestor still TSrcA): unconverted, action skipped' (($u.Count -eq 1) -and ($u[0].ancestor_state -eq 'unconverted') -and ($u[0].action -eq 'skipped')) ($u | ConvertTo-Json -Compress)
$c = Inh $j 'rcode'
Check 'A7 rcode (code-only use, N2a): action code, ancestor RBase, converted, line = its first code reference' `
  (($c.Count -eq 1) -and ($c[0].action -eq 'code') -and ($c[0].ancestor_unit -eq 'RBase') -and ($c[0].ancestor_state -eq 'converted') -and ($c[0].line -eq 22)) ($c | ConvertTo-Json -Compress)
$rk = @($j.items | Where-Object { $_.kind -eq 'inherited-instance-retyped' })
Check 'A8 items[]: one inherited-instance-retyped per retyped instance (rbtn, rnest, fb), field converted' `
  (($rk.Count -eq 3) -and (@($rk | Where-Object { $_.field -ne 'converted' }).Count -eq 0)) ($rk | ConvertTo-Json -Compress)
$sk = @($j.items | Where-Object { $_.kind -eq 'inherited-instance-skipped' })
Check 'A9 items[]: inherited-instance-skipped only for ubtn' (($sk.Count -eq 1) -and ($sk[0].instance -eq 'ubtn')) ($sk | ConvertTo-Json -Compress)
$sum = @($j.converted).Count + @($j.access_sites).Count + @($j.creator_sites).Count + @($j.todos).Count + @($j.reemit_notes).Count + @($j.warnings).Count
Check 'A10 invariant: items.length = sum of the six arrays' (($null -ne $j) -and (@($j.items).Count -eq $sum)) "items=$(@($j.items).Count) sum=$sum"
Check 'A11 no field-decl warning for an inherited instance (the descendant declares no field)' `
  (@($j.items | Where-Object { $_.kind -eq 'field-decl-not-retyped' }).Count -eq 0) ($j.warnings -join ' | ')

# ---- --apply -------------------------------------------------------------------
$r = ApplyTo @('RChild.pas') 'retype.rules' @('--apply', '--no-backup')
$dfm = Text 'RChild.dfm'
$pas = Text 'RChild.pas'
Check 'B1 --apply exits 0' ($r.Code -eq 0) $r.Out
$bb = Block $dfm 'inherited rbtn: TDstB'
Check 'B2 rbtn retyped, keyword kept: inherited rbtn: TDstB, Title/Hint carried' `
  (($bb -ne '') -and ($bb -match "Title = 'child'") -and ($bb -match "Hint = 'h'")) $dfm
Check 'B3 the retyped block writes NO resolved default (Size) and NO #default (Color) -- absent means inherited' `
  (($bb -ne '') -and -not ($bb -match 'Size =') -and -not ($bb -match 'Color =')) $bb
$nb = Block $dfm 'inherited rnest: TDstB'
Check 'B4 nested rnest retyped under the unchanged inherited rpnl: TBox' `
  (($nb -match "Title = 'n2'") -and ($dfm -match '(?m)^  inherited rpnl: TBox\r?$')) $dfm
$fbb = Block $dfm 'inherited fb: TDstB'
Check 'B5 inline frame kept as inline frm: TRFrame; its child fb retyped' `
  (($fbb -match "Title = 'f2'") -and ($dfm -match '(?m)^  inline frm: TRFrame\r?$')) $dfm
$ob = Block $dfm 'object own: TDstB'
Check 'B6 positive control: own instance -> object own: TDstB, Title carried, defaulted Size=3 carried, #default Color=5 written' `
  (($ob -match "Title = 'own'") -and ($ob -match 'Size = 3') -and ($ob -match 'Color = 5')) $ob
Check 'B7 ubtn (unconverted ancestor) byte-unchanged' ($dfm.Contains("  inherited ubtn: TSrcA`r`n    Caption = 'u2'`r`n  end`r`n")) $dfm
Check 'B8 code: rbtn.Title, rcode.Title (N2a), own.Title, rnest.Hint := rbtn.Title' `
  (($pas -match "rbtn\.Title := 'x';") -and ($pas -match "rcode\.Title := 'y';") -and ($pas -match "own\.Title := 'z';") -and `
   ($pas -match 'rnest\.Hint := rbtn\.Title;')) $pas
Check 'B9 code: ubtn.Caption (unconverted ancestor) untouched' ($pas -match "ubtn\.Caption := 'u';") $pas
Check 'B10 own field retyped and LibB added to the INTERFACE uses (C13 a)' `
  (($pas -match 'own: TDstB;') -and ($pas -match 'System\.Classes, Vcl\.Forms, LibA, RMid, RFrame, LibB;')) $pas

# ---- N2a: a code-only descendant -------------------------------------------------
$r = ApplyTo @('RCode.pas') 'retype.rules' @('--format', 'json')
$j = Json $r.Out
$c = if ($j) { Inh $j 'rcode' } else { @() }
Check 'C1 RCode (no own instance, no .dfm re-open): exit 0, ok, component_part applied, rcode action code' `
  (($r.Code -eq 0) -and ($null -ne $j) -and $j.ok -and ($j.component_part -eq 'applied') -and ($c.Count -eq 1) -and ($c[0].action -eq 'code')) $r.Out
Check 'C2 two access sites rewritten' (@($j.access_sites).Count -eq 2) ($j.access_sites -join ' | ')
$r = ApplyTo @('RCode.pas') 'retype.rules' @('--apply', '--no-backup')
$t = Text 'RCode.pas'
Check 'C3 --apply: S := rcode.Title; rcode.Title := S + ''!''; LibB added' `
  (($r.Code -eq 0) -and ($t -match 'S := rcode\.Title;') -and ($t -match "rcode\.Title := S \+ '!';") -and ($t -match '\bLibB\b')) ($r.Out + "`n" + $t)
$hS = (Get-FileHash (P 'RShadow.pas')).Hash
$r = ApplyTo @('RShadow.pas') 'retype.rules' @('--format', 'json')
$j = Json $r.Out
Check 'C4 RShadow: a LOCAL named rcode is not the ancestor field -- no code entry, so nothing to convert (the pre-N2 "no convertible instances" error, exit 1)' `
  (($r.Code -eq 1) -and ($j.error -match 'no convertible instances') -and ($null -ne $j) -and (@($j.inherited).Count -eq 0) -and (@($j.access_sites).Count -eq 0)) $r.Out

# ---- --only ------------------------------------------------------------------------
Write-Ascii (P 'RChild2.pas') @"
unit RChild2;

interface

uses
  System.Classes, Vcl.Forms, LibA, RMid;

type
  TRChild2 = class(TRMid)
    own: TSrcA;
    procedure Touch;
  end;

implementation

{`$R *.dfm}

procedure TRChild2.Touch;
begin
  rbtn.Caption := 'x';
  rcode.Caption := 'y';
  own.Caption := 'z';
end;

end.
"@
Write-Ascii (P 'RChild2.dfm') @'
inherited RChild2: TRChild2
  inherited rbtn: TSrcA
    Caption = 'child'
  end
  inherited rpnl: TBox
    inherited rnest: TSrcA
      Caption = 'n2'
    end
  end
  object own: TSrcA
    Caption = 'own'
  end
end
'@
$idx = & $Exe index $WorkDir --db $db 2>&1
$r = ApplyTo @('RChild2.pas') 'retype.rules' @('--only', 'rbtn', '--format', 'json')
$j = Json $r.Out
Check 'D1 --only rbtn: only rbtn in inherited[] (retyped), nothing else converted, only_matched [rbtn]' `
  (($r.Code -eq 0) -and ($null -ne $j) -and (@($j.inherited).Count -eq 1) -and (@($j.inherited)[0].name -eq 'rbtn') -and `
   (@($j.inherited)[0].action -eq 'retyped') -and (@($j.converted).Count -eq 1) -and ((@($j.only_matched) -join ',') -eq 'rbtn')) $r.Out
Check 'D2 --only rbtn: only the rbtn.Caption site rewritten, not rcode/own' `
  ((@($j.access_sites).Count -eq 1) -and (@($j.access_sites | Where-Object { $_ -notmatch '^rbtn\.' }).Count -eq 0)) ($j.access_sites -join ' | ')
$r = ApplyTo @('RChild2.pas') 'retype.rules' @('--only', 'rcode', '--format', 'json')
$j = Json $r.Out
Check 'D3 --only rcode (code-only): rcode action code, only_matched [rcode], only_unmatched [], one access site' `
  (($r.Code -eq 0) -and ($null -ne $j) -and (@($j.inherited).Count -eq 1) -and (@($j.inherited)[0].action -eq 'code') -and `
   ((@($j.only_matched) -join ',') -eq 'rcode') -and (@($j.only_unmatched).Count -eq 0) -and (@($j.access_sites).Count -eq 1)) $r.Out

# ---- batch ---------------------------------------------------------------------------
$r = ApplyTo @('RChild2.pas', 'RCode.pas') 'retype.rules' @('--format', 'json')
$j = Json $r.Out
$u0 = if ($j) { @($j.units)[0] } else { $null }
Check 'E1 batch RChild2 + RCode: exit 0, apply-batch/1, RChild2 retypes rbtn and rnest' `
  (($r.Code -eq 0) -and ($null -ne $j) -and ($j.schema -eq 'apply-batch/1') -and ($null -ne $u0) -and `
   (@($u0.inherited | Where-Object { $_.action -eq 'retyped' }).Count -eq 2)) $r.Out

# ---- the capability ----------------------------------------------------------------
$o = (& $Exe info --json 2>$null) -join "`n"
$ij = Json $o
Check 'F1 info --json: capabilities.inherited_retype is the JSON literal true' `
  (($null -ne $ij) -and ($ij.capabilities.inherited_retype -is [bool]) -and ($ij.capabilities.inherited_retype -eq $true)) $o

# ---- the converted descendants compile against the converted ancestors -------------
if (-not $NoCompile) {
  $CRLF = "`r`n"
  [IO.File]::WriteAllText((P 'P.dpr'), (@(
    'program P;', '', 'uses', '  RChild, RCode, RShadow;', '',
    'begin', 'end.') -join $CRLF) + $CRLF, [Text.Encoding]::ASCII)
  New-Item -ItemType Directory (P 'bin'), (P 'dcu') -Force | Out-Null
  $bat = P 'compile.bat'; $log = P 'compile.log'
  [IO.File]::WriteAllText($bat, (@('@echo off', "call `"$RsVars`"", "cd /d `"$WorkDir`"",
    "dcc64 -Q -B -NSSystem;Vcl;Winapi;System.Win -E`"$WorkDir\bin`" -NU`"$WorkDir\dcu`" P.dpr", 'echo BUILD_EXITCODE=%ERRORLEVEL%') -join $CRLF), [Text.Encoding]::ASCII)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait | Out-Null
  $cl = Get-Content $log -Raw -ErrorAction SilentlyContinue
  $errLines = @(($cl -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal' })
  Check 'G1 RChild and RCode compile with dcc64 after --apply (private -E/-NU)' (($cl -match 'BUILD_EXITCODE=0') -and ($errLines.Count -eq 0)) ($errLines -join ' | ')
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_convert_apply_inh_retype_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
