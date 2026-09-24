<#
  run_enum_read_inside_with.ps1 -- rule `enum-read-inside-with`
  (docs\INBOX-lint-rules-from-new-facts-2026-09-23.md, section 1).

  THE BUG CLASS. Inside `with R do`, a bare `cmdDelta` binds to R's member of
  that name when R's type declares one -- the compiler never says so. Up to
  resolver 1.7.0 the index bound the same bare read to the ENUM VALUE cmdDelta,
  because `with` scope was not modelled (risk R7, docs\MEASURED-enum-value-refs-
  2026-09-23.md).

  RESOLVER 1.8.0 MODELS THE WITH SCOPE. Where it can type the with target and
  see its whole surface, the read now binds to the MEMBER -- the RecPositive and
  ObjPositive sites below, which used to be this rule's positives, are its
  R7-CLOSED controls now, and the rule is silent there because the index no
  longer records the enum value. What is left is the residual the resolver
  CANNOT decide: a target whose type it cannot resolve (here: a type name two
  used units both declare; in real code, mostly a library class the project
  index does not hold). There the enum pass keeps its binding, and this rule --
  which types with targets by NAME across the project and library indexes --
  is the reporter. DupTarget below is that positive.

  WHY A NEW RULE AND NOT with-hides-outer-symbol. That rule's hidden side is a
  local, a Self member or an outer with layer; a unit-level enum value is none
  of those, and its with-target surface admits CLASSES only, while the spec's
  own positive control is a RECORD. Measured 2026-09-23 before this rule
  existed: the positive fixture below produced no with-hides-outer-symbol
  finding. The OVERLAP section pins that, so a future widening of the older
  rule that starts to cover this case is noticed and one of the two is retired.

  PRECISION over volume: the finding needs BOTH a same-named member on a with
  target AND the index's own binding of that read to an enum_value symbol. A
  mere "enum read inside a with-bearing routine" is the 178-site population on
  ORM3 CLIENT and must stay silent -- the NEGATIVE controls below.

  Run from a NEUTRAL CWD, pwsh 7.
#>
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-enumwith"
)
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
# A fresh directory per run, not a delete: the index of a previous run must
# never answer this one.
$WorkDir = Join-Path $WorkDir ([guid]::NewGuid().ToString('N'))
$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir -Force | Out-Null

function Emit([string]$name, [string]$text) {
  [System.IO.File]::WriteAllText((Join-Path $srcDir $name),
    (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

Emit 'uEwTypes.pas' @'
unit uEwTypes;
interface
type
  TEwCmd = (cmdDelta, cmdOther, cmdPlain);

  TEwDup = record
    cmdPlain: Integer;
  end;

  TEwRec = record
    cmdDelta: Integer;
    Caption : string;
  end;

  TEwObj = class
  public
    cmdOther: Integer;
    Caption : string;
  end;
implementation
end.
'@

# The SECOND declaration of TEwDup: with both units used, the resolver cannot
# pick one (ResolveTypeNameToSymbol declines an ambiguous name), so the target
# of `with D do` is untypable to it -- the residual this rule reports.
Emit 'uEwTypes2.pas' @'
unit uEwTypes2;
interface
type
  TEwDup = record
    cmdPlain: Integer;
    Tag     : Integer;
  end;
implementation
end.
'@

# Line numbers matter: the assertions match on them.
#   15  RECORD, R7 CLOSED (was the spec's own positive): binds TEwRec.cmdDelta now
#   22  CLASS,  R7 CLOSED: binds TEwObj.cmdOther now
#   29  NEG: enum read, no same-named member on the with target
#   36  NEG: qualified TEwCmd.cmdDelta
#   43  NEG: with-member read that is not an enum value
#   49  NEG: bare enum read outside any with
#   56  POSITIVE: the with target is untypable to the resolver (TEwDup twice)
Emit 'uEwUse.pas' @'
unit uEwUse;
interface
uses uEwTypes, uEwTypes2;
procedure RecPositive(var R: TEwRec);
procedure ObjPositive(const O: TEwObj);
procedure NoMember(var R: TEwRec);
procedure Qualified(var R: TEwRec);
procedure NotEnum(var R: TEwRec);
procedure NoWith;
implementation
procedure RecPositive(var R: TEwRec);
var X: Integer;
begin
  with R do
    X := cmdDelta;
  if X > 0 then R.Caption := 'a';
end;
procedure ObjPositive(const O: TEwObj);
var X: Integer;
begin
  with O do
    X := cmdOther;
  if X > 0 then O.Caption := 'b';
end;
procedure NoMember(var R: TEwRec);
var C: TEwCmd;
begin
  with R do
    C := cmdPlain;
  if C = cmdOther then R.Caption := 'c';
end;
procedure Qualified(var R: TEwRec);
var C: TEwCmd;
begin
  with R do
    C := TEwCmd.cmdDelta;
  if C = cmdOther then R.Caption := 'd';
end;
procedure NotEnum(var R: TEwRec);
var S: string;
begin
  with R do
    S := Caption;
  if S <> '' then R.cmdDelta := 1;
end;
procedure NoWith;
var C: TEwCmd;
begin
  C := cmdDelta;
  if C = cmdOther then Exit;
end;
procedure DupTarget(var D: TEwDup);
var C: TEwCmd;
begin
  with D do
    C := cmdPlain;
  if C = cmdOther then Exit;
end;
end.
'@

$manifest = Join-Path $WorkDir 'manifest.drag-lint.json'
$mtext = '{' + [char]10 +
  '  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },' + [char]10 +
  '  "indexes": { "outDir": "out", "sections": [ { "name": "SecEw", "db": "ew.sqlite", "include": ["src"] } ] }' + [char]10 +
  '}'
[System.IO.File]::WriteAllText($manifest, $mtext, [System.Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'out\ew.sqlite'
$cfgOff = Join-Path $WorkDir 'off.json'
[System.IO.File]::WriteAllText($cfgOff, '{ "disabled": [ "enum-read-inside-with" ] }',
                               [System.Text.Encoding]::ASCII)
$useSrc = Join-Path $srcDir 'uEwUse.pas'

Push-Location C:\TEMP
try {
  & $Exe index --all --config $manifest --only SecEw --jobs 1 2>&1 | Out-Null
  if (-not (Test-Path $db)) {
    Write-Host "FATAL: index did not produce $db" -ForegroundColor Red; exit 2
  }
  $onOut   = & $Exe lint-all --db $db --quiet 2>&1 | Out-String
  $offOut  = & $Exe lint-all --db $db --config $cfgOff --quiet 2>&1 | Out-String
  $fileOut = & $Exe lint $useSrc --db $db --rule enum-read-inside-with --quiet 2>&1 | Out-String
  # What the index recorded at the old positive (15, R7 CLOSED) and at the
  # residual (56): the rule reads exactly these bindings.
  $bind15 = & $Exe sql --db $db --query ("select s.kind || ':' || s.qualified_name from refs r join symbols s on s.id = r.symbol_id " +
                                          "where r.name_text = 'cmdDelta' and r.start_line = 15") 2>&1 | Out-String
  $bind56 = & $Exe sql --db $db --query ("select s.kind || ':' || s.qualified_name from refs r join symbols s on s.id = r.symbol_id " +
                                          "where r.name_text = 'cmdPlain' and r.start_line = 56") 2>&1 | Out-String
} finally { Pop-Location }

$lines = @($onOut -split "`r?`n" | Where-Object { $_ -match 'enum-read-inside-with' })
function HitAt([string]$text, [int]$line) {
  @($text -split "`r?`n" | Where-Object { $_ -match 'enum-read-inside-with' -and $_ -match ('uEwUse\.pas:' + $line + ':') })
}

Write-Host ''
Write-Host 'PRECONDITIONS -- what the resolver (1.8.0, with scope modelled) recorded' -ForegroundColor Cyan
Check 'R7 CLOSED: line 15 cmdDelta is bound to the FIELD TEwRec.cmdDelta, not the enum value' `
  (($bind15 -match 'field:uEwTypes\.TEwRec\.cmdDelta') -and ($bind15 -notmatch 'enum_value')) ($bind15.Trim())
Check 'RESIDUAL: line 56 cmdPlain (untypable with target) is still bound to the enum value' `
  ($bind56 -match 'enum_value:uEwTypes\.TEwCmd\.cmdPlain') ($bind56.Trim())

Write-Host ''
Write-Host 'THE FINDING' -ForegroundColor Cyan
$dup = HitAt $onOut 56
Check 'UNDECIDABLE TARGET: with D do C := cmdPlain fires once' ($dup.Count -eq 1) ("got " + $dup.Count + " of " + $lines.Count + " total")
Check 'and it names the with-target member that wins' (($dup -join ' ') -match 'TEwDup\.cmdPlain') ''
Check 'and it names the enum value it is NOT' (($dup -join ' ') -match 'TEwCmd\.cmdPlain') ''
Check 'and it is a warning' (($dup -join ' ') -match '\[warning\]') ''
Check 'R7 CLOSED: the RECORD site (15) is silent -- the index binds the member now' ((HitAt $onOut 15).Count -eq 0) ''
Check 'R7 CLOSED: the CLASS site (22) is silent -- the index binds the member now' ((HitAt $onOut 22).Count -eq 0) ''

Write-Host ''
Write-Host 'THE NEGATIVE CONTROLS' -ForegroundColor Cyan
Check 'NO MEMBER: an enum read in a with body with no same-named member is SILENT' `
  ((HitAt $onOut 29).Count -eq 0) 'RED means the rule fires on the population, not on shadowing'
Check 'QUALIFIED: TEwCmd.cmdDelta inside the with is SILENT' ((HitAt $onOut 36).Count -eq 0) ''
Check 'NOT ENUM: a with-member read that names no enum value is SILENT' ((HitAt $onOut 43).Count -eq 0) ''
Check 'NO WITH: a bare enum read outside any with is SILENT' ((HitAt $onOut 49).Count -eq 0) ''
Check 'exactly the one positive, nothing else' ($lines.Count -eq 1) ("got " + $lines.Count)

Write-Host ''
Write-Host 'OVERLAP -- with-hides-outer-symbol does not already cover this' -ForegroundColor Cyan
$overlap = @($onOut -split "`r?`n" | Where-Object { $_ -match 'with-hides-outer-symbol' -and $_ -match 'uEwUse\.pas:(15|22|56):' })
Check 'with-hides-outer-symbol is silent on the positive and the R7-closed sites' ($overlap.Count -eq 0) `
  'if this goes RED the older rule now covers the case -- retire one of the two'

Write-Host ''
Write-Host 'SINGLE-FILE lint --rule' -ForegroundColor Cyan
Check 'lint <file> --rule enum-read-inside-with reports the positive' `
  ((HitAt $fileOut 56).Count -eq 1) `
  'RED means the per-file path never runs the check under --rule'

Write-Host ''
Write-Host 'OFF SWITCH' -ForegroundColor Cyan
Check 'a disabling config reports nothing' (-not ($offOut -match 'enum-read-inside-with')) ''
Check 'POSITIVE CONTROL: the off run still produced other findings' ($offOut -match ':\d+:\d+') `
  'a silent run would pass the check above for the wrong reason'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
