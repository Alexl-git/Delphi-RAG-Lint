<#
  run_enum_bare_read_scoped.ps1 -- X4: the $SCOPEDENUMS fact on enum types and
  the rule `enum-bare-read-scoped` (docs\INBOX-new-rules-from-graph-and-converter-
  facts.md item A3).

  THE FACT. Under the SCOPEDENUMS ON switch Delphi does NOT add an enum's values
  to the enclosing scope: `TFoo.Value` is the only spelling that compiles. The
  extractor now records the switch state in force at each enum TYPE declaration
  as symbols.directives = 'scopedenums' (empty otherwise). The switch is read
  from the text the parser sees, which is the PREPROCESSED text: a switch inside
  an inactive conditional branch is blanked and must not count, and neither may
  one inside a // or brace comment.

  THE RULE. A BARE read (no receiver, no qualifier) that the index bound to a
  value of a scoped enum cannot be what the compiler binds -- the bare name is
  either something else of the same name or code that does not compile. Either
  way the index's binding is wrong and the reader must verify it.

  Positive AND negative controls; a precondition pins that the positive site is
  really BOUND to the enum value, so a silent rule cannot pass for the wrong
  reason. Run from a NEUTRAL CWD, pwsh 7.
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

function Emit([string]$name, [string]$text) {
  [System.IO.File]::WriteAllText((Join-Path $srcDir $name),
    (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

# Line numbers matter for the reader only; the assertions key on type names.
Emit 'uSeTypes.pas' @'
unit uSeTypes;
interface
type
  TSePlain = (spAlpha, spBeta);
{$SCOPEDENUMS ON}
  TSeScoped = (ssAlpha, ssBeta);
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
implementation
end.
'@

# Line numbers matter: the assertions match on them.
#   15  POSITIVE: bare ssAlpha, TSeScoped is scoped
#   16  NEG: qualified TSeScoped.ssBeta
#   21  NEG: qualified TSeScoped.ssAlpha
#   27  NEG: bare spAlpha, TSePlain is not scoped
#   33  NEG: bare saAlpha, scoping switched OFF again
#   39  NEG: bare siAlpha, the ON switch sits in an inactive IFDEF branch
#   45  NEG: bare scAlpha, the ON text is only inside comments
#   51  POSITIVE: bare sxAlpha, TSeParen is scoped by the (*$ *) spelling
#   52  NEG: qualified TSeParen.sxBeta
Emit 'uSeUse.pas' @'
unit uSeUse;
interface
uses uSeTypes;
procedure BareScoped;
procedure Qualified;
procedure BarePlain;
procedure BareAfterOff;
procedure BareIfdef;
procedure BareComment;
procedure BareParen;
implementation
procedure BareScoped;
var E: TSeScoped;
begin
  E := ssAlpha;
  if E = TSeScoped.ssBeta then Exit;
end;
procedure Qualified;
var E: TSeScoped;
begin
  E := TSeScoped.ssAlpha;
  if E = TSeScoped.ssBeta then Exit;
end;
procedure BarePlain;
var P: TSePlain;
begin
  P := spAlpha;
  if P = spBeta then Exit;
end;
procedure BareAfterOff;
var A: TSeAfter;
begin
  A := saAlpha;
  if A = saBeta then Exit;
end;
procedure BareIfdef;
var I: TSeIfdef;
begin
  I := siAlpha;
  if I = siBeta then Exit;
end;
procedure BareComment;
var C: TSeComment;
begin
  C := scAlpha;
  if C = scBeta then Exit;
end;
procedure BareParen;
var X: TSeParen;
begin
  X := sxAlpha;
  if X = TSeParen.sxBeta then Exit;
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
  $bind13  = & $Exe sql --db $db --query ("select s.kind || ':' || s.qualified_name || ':' || coalesce(r.receiver_text, '') " +
                                          "from refs r join symbols s on s.id = r.symbol_id " +
                                          "where r.name_text = 'ssAlpha' and r.start_line = 15") 2>&1 | Out-String
  $onOut   = & $Exe lint-all --db $db --quiet 2>&1 | Out-String
  $offOut  = & $Exe lint-all --db $db --config $cfgOff --quiet 2>&1 | Out-String
  $fileOut = & $Exe lint $useSrc --db $db --rule enum-bare-read-scoped --quiet 2>&1 | Out-String
  $rules   = & $Exe rules --json 2>&1 | Out-String
} finally { Pop-Location }

function FactOf([string]$type) {
  $m = [regex]::Match($facts, '(?m)^\s*' + $type + '=(\S*)\s*$')
  if ($m.Success) { $m.Groups[1].Value } else { '<missing>' }
}
$lines = @($onOut -split "`r?`n" | Where-Object { $_ -match 'enum-bare-read-scoped' })
function HitAt([string]$text, [int]$line) {
  @($text -split "`r?`n" | Where-Object { $_ -match 'enum-bare-read-scoped' -and $_ -match ('uSeUse\.pas:' + $line + ':') })
}

Write-Host ''
Write-Host 'THE FACT -- symbols.directives on each enum type' -ForegroundColor Cyan
Check 'TSeScoped (after $SCOPEDENUMS ON) carries scopedenums' ((FactOf 'TSeScoped') -eq 'scopedenums') (FactOf 'TSeScoped')
Check 'TSeParen (the (*$ *) spelling, lower case) carries scopedenums' ((FactOf 'TSeParen') -eq 'scopedenums') (FactOf 'TSeParen')
Check 'NEG: TSePlain (before any switch) carries nothing' ((FactOf 'TSePlain') -eq '') (FactOf 'TSePlain')
Check 'NEG: TSeAfter (after $SCOPEDENUMS OFF) carries nothing' ((FactOf 'TSeAfter') -eq '') (FactOf 'TSeAfter')
Check 'NEG: TSeIfdef (ON only in an inactive IFDEF branch) carries nothing' ((FactOf 'TSeIfdef') -eq '') (FactOf 'TSeIfdef')
Check 'NEG: TSeComment (ON only inside comments) carries nothing' ((FactOf 'TSeComment') -eq '') (FactOf 'TSeComment')

Write-Host ''
Write-Host 'E14 (1.36.0) -- the resolver now DECLINES the bare scoped read' -ForegroundColor Cyan
# Until E14 the index bound `E := ssAlpha` to the scoped value and this rule
# flagged that wrong edge. The resolver now declines it (TEnumValueDecl.Scoped;
# guard run_enum_scoped_decline.ps1), so the rule has no input left on a fresh
# index: its positives below are inverted DELIBERATELY, not weakened. Whether
# the rule is retired or retargeted (e.g. at the unbound bare read) is an owner
# decision recorded in the E14 lane report.
Check 'line 15 ssAlpha is NOT bound (E14 decline)' ($bind13 -notmatch 'enum_value:') ($bind13.Trim())
$h13 = HitAt $onOut 15
Check 'BARE SCOPED: E := ssAlpha no longer fires (nothing bound)' ($h13.Count -eq 0) ("got " + $h13.Count + " of " + $lines.Count + " total")
Check 'BARE SCOPED (*$ *) spelling: X := sxAlpha no longer fires' ((HitAt $onOut 51).Count -eq 0) ''
Check 'single-file lint --rule agrees: silent on both' `
  (((HitAt $fileOut 15).Count -eq 0) -and ((HitAt $fileOut 51).Count -eq 0)) ''
Write-Host 'THE NEGATIVE CONTROLS' -ForegroundColor Cyan
Check 'QUALIFIED: TSeScoped.ssBeta (16) is SILENT' ((HitAt $onOut 16).Count -eq 0) ''
Check 'QUALIFIED: TSeScoped.ssAlpha (21) is SILENT' ((HitAt $onOut 21).Count -eq 0) ''
Check 'UNSCOPED: bare spAlpha (27) is SILENT' ((HitAt $onOut 27).Count -eq 0) ''
Check 'SWITCHED OFF: bare saAlpha (33) is SILENT' ((HitAt $onOut 33).Count -eq 0) ''
Check 'INACTIVE BRANCH: bare siAlpha (39) is SILENT' ((HitAt $onOut 39).Count -eq 0) ''
Check 'COMMENT ONLY: bare scAlpha (45) is SILENT' ((HitAt $onOut 45).Count -eq 0) ''
Check 'QUALIFIED: TSeParen.sxBeta (52) is SILENT' ((HitAt $onOut 52).Count -eq 0) ''
Check 'nothing at all (was: exactly the two positives before E14)' ($lines.Count -eq 0) ("got " + $lines.Count)

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
