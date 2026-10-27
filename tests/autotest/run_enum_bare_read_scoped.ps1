<#
  run_enum_bare_read_scoped.ps1 -- the $SCOPEDENUMS fact on enum types (X4) and
  the rule `enum-bare-read-scoped`, RETARGETED 2026-10-26 (owner ruling, lane
  XT-SCOPED) after E14 made the resolver decline a bare scoped read.

  THE FACT. Under the SCOPEDENUMS ON switch Delphi does NOT add an enum's values
  to the enclosing scope: `TFoo.Value` is the only spelling that compiles. The
  extractor records the switch state in force at each enum TYPE declaration as
  symbols.directives = 'scopedenums' (empty otherwise), read from PREPROCESSED
  text: a switch in an inactive branch or inside a comment does not count.

  THE RULE. A BARE read (no receiver) whose name is the name of a value of a
  scoped enum VISIBLE from the site (declared in the same unit or in a unit the
  file uses):
   (a) WARNING when the index bound it to ANOTHER symbol (unit const/var,
       field or property of the class or an ancestor, local) AND the types say
       the enum may have been meant (owner ruling 2026-10-26, type match):
       (i) that symbol is OF the scoped enum type, or (ii) the site's target
       is typed as the enum -- the LHS of `:=`, or the other operand of
       `=`/`<>`/`in` (set of the enum). A target the index cannot type (an
       argument, a statement split over lines) is NOT warned: no guessing;
   (b) HINT when it stayed UNBOUND and no other symbol carries the name:
       under SCOPEDENUMS ON it does not compile (E2003); write TEnum.Value.
  Short un-prefixed values (TSeAlign.Left/Client/Top) are covered.
  NOT a finding: the qualified form, a value of a non-scoped enum, a scoped
  enum in a unit the site does not use, a const that ALIASES the scoped value
  (`X = TEnum.X`, the Vcl.Dialogs compatibility idiom), an UNBOUND bare name that another
  symbol also carries (the resolver declined for its own reason -- an untypable
  with target -- not E2003), a site in an inactive
  branch (the index has no ref there).

  Each positive is located by a {#tag} marker on its line; a precondition pins
  each (a) site's binding, so a silent rule cannot pass for the wrong reason.
  Run from a NEUTRAL CWD, pwsh 7.
#>
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-enumscoped-$PID"
)
try {
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
$WorkDir = Join-Path $WorkDir ([guid]::NewGuid().ToString('N'))
$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir -Force | Out-Null

$script:Texts = @{}
function Emit([string]$name, [string]$text) {
  $script:Texts[$name] = ($text -replace "`r`n", "`n")
  [System.IO.File]::WriteAllText((Join-Path $srcDir $name),
    (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}
# 1-based line of the line carrying {#tag} in a fixture; FATAL when absent or doubled.
function LineOf([string]$file, [string]$tag) {
  $ls = $script:Texts[$file] -split "`n"
  $hit = @(for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i].Contains('{#' + $tag + '}')) { $i + 1 } })
  if ($hit.Count -ne 1) { Write-Host "FATAL: marker $tag found $($hit.Count)x in $file" -ForegroundColor Red; exit 2 }
  $hit[0]
}

Emit 'uSeTypes.pas' @'
unit uSeTypes;
interface
type
  TSePlain = (spAlpha, spBeta);
{$SCOPEDENUMS ON}
  TSeScoped = (ssAlpha, ssBeta);
  TSeColor = (csOne, csTwo, csThree, csFour, csFive, csSix, csSeven, csProp, csAlias, csAliasIn, csAliasHere, csWith, csSame);
  TSeAlign = (Left, Client, Top);
{$SCOPEDENUMS OFF}
  TSeAfter = (saAlpha, saBeta);
{$IFDEF X4_NEVER_DEFINED}
{$SCOPEDENUMS ON}
{$ENDIF}
  TSeIfdef = (siAlpha, siBeta);
// {$SCOPEDENUMS ON}
{ a comment, not a directive: $SCOPEDENUMS ON }
  TSeComment = (scAlpha, scBeta);
(*$scopedenums on*)
  TSeParen = (sxAlpha, sxBeta);
const
  csAlias = TSeColor.csAlias;
  csAliasIn = uSeTypes.TSeColor.csAliasIn;
implementation
end.
'@

# A scoped enum in a unit uSeUse does NOT use: its names are not visible there.
Emit 'uSeHidden.pas' @'
unit uSeHidden;
interface
{$SCOPEDENUMS ON}
type
  TSeHidden = (shOnly, shTwo);
implementation
end.
'@

# A unit-level const/var and an ancestor class in a used unit: the (a) targets.
Emit 'uSeBase.pas' @'
unit uSeBase;
interface
type
  TSeRec = record
    csWith: Integer;
  end;
  TSeBase = class
  protected
    csThree: Integer;
    FProp: Integer;
    property csProp: Integer read FProp;
    property Left: Integer read FProp;
    property Top: Integer read FProp;
    FAlign: TSeAlign;
    property Client: TSeAlign read FAlign;
  end;
implementation
end.
'@

Emit 'uSeUse.pas' @'
unit uSeUse;
interface
uses uSeTypes, uSeBase;
const
  csOne = 1;
  csAliasHere = uSeTypes.TSeColor.csAliasHere;
var
  csTwo: Integer;
  csSame: TSeColor;
type
  TSeDerived = class(TSeBase)
    csFour: Integer;
    procedure UseThem;
  end;
procedure TakeColor(V: TSeColor);
procedure BareScoped;
procedure Qualified;
procedure BarePlain;
procedure BareAfterOff;
procedure BareIfdef;
procedure BareComment;
procedure BareParen;
implementation
procedure TSeDerived.UseThem;
var
  csFive: Integer;
  K: Integer;
  X: TSeColor;
  A: TSeAlign;
  XS: set of TSeColor;
begin
  XS := [];
  X := csOne; {#A_CONST}
  X := csTwo; {#A_VAR}
  X := csThree; {#A_ANCFIELD}
  X := csProp; {#A_ANCPROP}
  X := csFour; {#A_FIELD}
  csFive := 0;
  X := csFive; {#A_LOCAL}
  K := csOne; {#N_INTTARGET}
  TakeColor(csTwo); {#N_ARG_UNTYPED}
  K := Ord(csSame); {#A_SAMETYPE_VAR}
  A := Client; {#A_SAMETYPE_PROP}
  A := Top; {#A_ENUMTARGET}
  if A = Top then Exit; {#A_ENUMCMP}
  X := csSix; {#B_UNBOUND}
  X := TSeColor.csSeven; {#N_QUAL}
  X := csAlias; {#N_ALIAS}
  if csAliasIn in XS then Exit; {#N_ALIAS_IN}
  if csAliasHere in XS then Exit; {#N_ALIAS_HERE}
  K := shOnly; {#N_HIDDEN}
  K := Left; {#N_UNPREFIXED_BOUND}
  with NotDeclaredAnywhere do
    K := csWith; {#N_UNBOUND_OTHER}
{$IFDEF X4_NEVER_DEFINED}
  X := csSeven; {#N_INACTIVE}
{$ENDIF}
  if K = Ord(X) then Exit;
end;
procedure TakeColor(V: TSeColor);
begin
end;
procedure BareScoped;
var E: TSeScoped;
begin
  E := ssAlpha; {#B_SSALPHA}
  if E = TSeScoped.ssBeta then Exit; {#N_QUAL2}
end;
procedure Qualified;
var E: TSeScoped;
begin
  E := TSeScoped.ssAlpha; {#N_QUAL3}
  if E = TSeScoped.ssBeta then Exit;
end;
procedure BarePlain;
var P: TSePlain;
begin
  P := spAlpha; {#N_PLAIN}
  if P = spBeta then Exit;
end;
procedure BareAfterOff;
var A: TSeAfter;
begin
  A := saAlpha; {#N_AFTEROFF}
  if A = saBeta then Exit;
end;
procedure BareIfdef;
var I: TSeIfdef;
begin
  I := siAlpha; {#N_IFDEFSWITCH}
  if I = siBeta then Exit;
end;
procedure BareComment;
var C: TSeComment;
begin
  C := scAlpha; {#N_COMMENTSWITCH}
  if C = scBeta then Exit;
end;
procedure BareParen;
var X: TSeParen;
begin
  X := sxAlpha; {#B_SXALPHA}
  if X = TSeParen.sxBeta then Exit; {#N_QUAL4}
end;
end.
'@

$manifest = Join-Path $WorkDir 'manifest.drag-lint.json'
$mtext = '{' + [char]10 +
  '  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },' + [char]10 +
  '  "indexes": { "outDir": "out", "sections": [ { "name": "SecSe", "db": "se.sqlite", "include": ["src"] } ] }' + [char]10 +
  '}'
[System.IO.File]::WriteAllText($manifest, $mtext, [System.Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'out\se.sqlite'
$cfgOff = Join-Path $WorkDir 'off.json'
[System.IO.File]::WriteAllText($cfgOff, '{ "disabled": [ "enum-bare-read-scoped" ] }',
                               [System.Text.Encoding]::ASCII)
$useSrc = Join-Path $srcDir 'uSeUse.pas'

Push-Location C:\TEMP
try {
  & $Exe index --all --config $manifest --only SecSe --jobs 1 2>&1 | Out-Null
  if (-not (Test-Path $db)) {
    Write-Host "FATAL: index did not produce $db" -ForegroundColor Red; exit 2
  }
  $facts   = & $Exe sql --db $db --query ("select name || '=' || coalesce(directives, '') from symbols " +
                                          "where kind = 'enum' order by name") 2>&1 | Out-String
  $binds   = & $Exe sql --db $db --query ("select r.start_line || '|' || r.name_text || '|' || coalesce(s.kind || ':' || s.qualified_name, 'NULL') " +
                                          "from refs r join files f on f.id = r.file_id left join symbols s on s.id = r.symbol_id " +
                                          "where f.path like '%uSeUse.pas' and r.kind = 'read' and coalesce(r.receiver_text, '') = ''") 2>&1 | Out-String
  $onOut   = & $Exe lint-all --db $db --quiet 2>&1 | Out-String
  $offOut  = & $Exe lint-all --db $db --config $cfgOff --quiet 2>&1 | Out-String
  $fileOut = & $Exe lint $useSrc --db $db --rule enum-bare-read-scoped --quiet 2>&1 | Out-String
  $rules   = & $Exe rules --json 2>&1 | Out-String
} finally { Pop-Location }

function FactOf([string]$type) {
  $m = [regex]::Match($facts, '(?m)^\s*' + $type + '=(\S*)\s*$')
  if ($m.Success) { $m.Groups[1].Value } else { '<missing>' }
}
function BindOf([int]$line, [string]$name) {
  $m = [regex]::Match($binds, '(?m)^\s*' + $line + '\|' + $name + '\|(\S+)\s*$')
  if ($m.Success) { $m.Groups[1].Value } else { '<no ref>' }
}
$lines = @($onOut -split "`r?`n" | Where-Object { $_ -match 'enum-bare-read-scoped' })
function HitAt([string]$text, [string]$tag) {
  $ln = LineOf 'uSeUse.pas' $tag
  @($text -split "`r?`n" | Where-Object { $_ -match 'enum-bare-read-scoped' -and $_ -match ('uSeUse\.pas:' + $ln + ':') })
}
function L([string]$tag) { LineOf 'uSeUse.pas' $tag }

Write-Host ''
Write-Host 'THE FACT -- symbols.directives on each enum type' -ForegroundColor Cyan
Check 'TSeScoped (after $SCOPEDENUMS ON) carries scopedenums' ((FactOf 'TSeScoped') -eq 'scopedenums') (FactOf 'TSeScoped')
Check 'TSeParen (the (*$ *) spelling, lower case) carries scopedenums' ((FactOf 'TSeParen') -eq 'scopedenums') (FactOf 'TSeParen')
Check 'NEG: TSePlain (before any switch) carries nothing' ((FactOf 'TSePlain') -eq '') (FactOf 'TSePlain')
Check 'NEG: TSeAfter (after $SCOPEDENUMS OFF) carries nothing' ((FactOf 'TSeAfter') -eq '') (FactOf 'TSeAfter')
Check 'NEG: TSeIfdef (ON only in an inactive IFDEF branch) carries nothing' ((FactOf 'TSeIfdef') -eq '') (FactOf 'TSeIfdef')
Check 'NEG: TSeComment (ON only inside comments) carries nothing' ((FactOf 'TSeComment') -eq '') (FactOf 'TSeComment')

Write-Host ''
Write-Host 'PRECONDITIONS -- what the index bound each site to' -ForegroundColor Cyan
Check 'A_CONST csOne binds to the unit const' ((BindOf (L 'A_CONST') 'csOne') -eq 'const:uSeUse.csOne') (BindOf (L 'A_CONST') 'csOne')
Check 'A_VAR csTwo binds to the unit var' ((BindOf (L 'A_VAR') 'csTwo') -match '^(var|variable):uSeUse\.csTwo$') (BindOf (L 'A_VAR') 'csTwo')
Check 'A_ANCFIELD csThree binds to the ANCESTOR field' ((BindOf (L 'A_ANCFIELD') 'csThree') -match '^field:uSeBase\.TSeBase\.csThree$') (BindOf (L 'A_ANCFIELD') 'csThree')
Check 'A_ANCPROP csProp binds to the ANCESTOR property' ((BindOf (L 'A_ANCPROP') 'csProp') -match '^property:uSeBase\.TSeBase\.csProp$') (BindOf (L 'A_ANCPROP') 'csProp')
Check 'A_FIELD csFour binds to the own field' ((BindOf (L 'A_FIELD') 'csFour') -match '^field:uSeUse\.TSeDerived\.csFour$') (BindOf (L 'A_FIELD') 'csFour')
Check 'A_LOCAL csFive binds to the local' ((BindOf (L 'A_LOCAL') 'csFive') -match '^local_var:') (BindOf (L 'A_LOCAL') 'csFive')
Check 'B_UNBOUND csSix is NOT bound (E14 decline)' ((BindOf (L 'B_UNBOUND') 'csSix') -eq 'NULL') (BindOf (L 'B_UNBOUND') 'csSix')
Check 'N_ALIAS csAlias binds to the aliasing const' ((BindOf (L 'N_ALIAS') 'csAlias') -eq 'const:uSeTypes.csAlias') (BindOf (L 'N_ALIAS') 'csAlias')
Check 'N_UNPREFIXED_BOUND Left binds to the ancestor property' ((BindOf (L 'N_UNPREFIXED_BOUND') 'Left') -eq 'property:uSeBase.TSeBase.Left') (BindOf (L 'N_UNPREFIXED_BOUND') 'Left')
Check 'A_SAMETYPE_PROP Client binds to the TSeAlign-typed property' ((BindOf (L 'A_SAMETYPE_PROP') 'Client') -eq 'property:uSeBase.TSeBase.Client') (BindOf (L 'A_SAMETYPE_PROP') 'Client')
Check 'A_ENUMTARGET Top binds to the Integer property' ((BindOf (L 'A_ENUMTARGET') 'Top') -eq 'property:uSeBase.TSeBase.Top') (BindOf (L 'A_ENUMTARGET') 'Top')
Check 'N_UNBOUND_OTHER csWith (under an untypable with) is NOT bound' ((BindOf (L 'N_UNBOUND_OTHER') 'csWith') -eq 'NULL') (BindOf (L 'N_UNBOUND_OTHER') 'csWith')
Check 'N_INACTIVE: the index has no ref in the inactive branch' ((BindOf (L 'N_INACTIVE') 'csSeven') -eq '<no ref>') (BindOf (L 'N_INACTIVE') 'csSeven')

Write-Host ''
Write-Host '(a) WARNING -- the bare name binds to ANOTHER symbol' -ForegroundColor Cyan
foreach ($t in @('A_CONST', 'A_VAR', 'A_ANCFIELD', 'A_ANCPROP', 'A_FIELD', 'A_LOCAL',
                 'A_SAMETYPE_VAR', 'A_SAMETYPE_PROP', 'A_ENUMTARGET', 'A_ENUMCMP')) {
  $h = @(HitAt $onOut $t)
  Check "$t fires exactly once, as a warning naming the enum value" (($h.Count -eq 1) -and ($h[0] -match 'warning') -and ($h[0] -match 'TSe(Color|Align)\.')) (($h -join ' | ').Trim())
}
$hc = @(HitAt $onOut 'A_CONST')
Check 'A_CONST message names what it binds to and the meant value' `
  (($hc.Count -eq 1) -and ($hc[0] -match 'uSeUse\.csOne \(const\)') -and ($hc[0] -match 'write TSeColor\.csOne')) (($hc -join ' | ').Trim())

Write-Host ''
Write-Host '(b) HINT -- the bare name stays UNBOUND' -ForegroundColor Cyan
foreach ($t in @('B_UNBOUND', 'B_SSALPHA', 'B_SXALPHA')) {
  $h = @(HitAt $onOut $t)
  Check "$t fires exactly once, as a hint" (($h.Count -eq 1) -and ($h[0] -match 'hint')) (($h -join ' | ').Trim())
}
$hb = @(HitAt $onOut 'B_UNBOUND')
Check 'B_UNBOUND message says write TSeColor.csSix and E2003' `
  (($hb.Count -eq 1) -and ($hb[0] -match 'write TSeColor\.csSix') -and ($hb[0] -match 'E2003')) (($hb -join ' | ').Trim())
Check 'single-file lint --rule agrees on an (a) and a (b) site' `
  (((HitAt $fileOut 'A_CONST').Count -eq 1) -and ((HitAt $fileOut 'B_UNBOUND').Count -eq 1)) ''

Write-Host ''
Write-Host 'THE NEGATIVE CONTROLS' -ForegroundColor Cyan
foreach ($t in @('N_QUAL', 'N_QUAL2', 'N_QUAL3', 'N_QUAL4', 'N_ALIAS', 'N_HIDDEN', 'N_INACTIVE',
                 'N_UNPREFIXED_BOUND', 'N_INTTARGET', 'N_ARG_UNTYPED', 'N_ALIAS_IN', 'N_ALIAS_HERE', 'N_UNBOUND_OTHER',
                 'N_PLAIN', 'N_AFTEROFF', 'N_IFDEFSWITCH', 'N_COMMENTSWITCH')) {
  Check "$t is SILENT" ((HitAt $onOut $t).Count -eq 0) ''
}
Check 'total = the 13 positives, nothing else' ($lines.Count -eq 13) ("got " + $lines.Count)

Write-Host ''
Write-Host 'CATALOGUE + OFF SWITCH' -ForegroundColor Cyan
Check 'rules --json lists enum-bare-read-scoped' ($rules -match '"enum-bare-read-scoped"') ''
Check 'a disabling config reports nothing' (-not ($offOut -match 'enum-bare-read-scoped')) ''
Check 'POSITIVE CONTROL: the off run still produced other findings' ($offOut -match ':\d+:\d+') `
  'a silent run would pass the check above for the wrong reason'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\drag-lint-enumscoped-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
