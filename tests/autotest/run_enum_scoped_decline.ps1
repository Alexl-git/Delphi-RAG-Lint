<#
  run_enum_scoped_decline.ps1 -- E14 (PLAN-2026-10-26 2c): the resolver DECLINES
  a bare read of a value of an enum declared under SCOPEDENUMS ON, and the
  SCOPEDENUMS switch is seen when it sits inside an INCLUDE file.

  WHY. Under SCOPEDENUMS ON Delphi does not put an enum's values into the
  enclosing scope: TFoo.Value is the only spelling that compiles. A bare name
  spelled like such a value is therefore something else (a const, a var) or code
  that does not compile -- never the value. Before E14 the resolver bound it to
  the value anyway (X4's rule enum-bare-read-scoped existed to flag exactly that
  wrong edge), and a scoped value also competed with a same-named const, so the
  const read was declined as shadowed/ambiguous: one wrong edge and one lost one.

  THE INCLUDE HALF. X4 read the switch only from the host's own text. The
  standard legacy idiom puts SCOPEDENUMS ON in a shared .inc, so every enum
  declared after such an include read as unscoped. The include's state now
  carries into the host at the include site, nested includes too; an include in
  an inactive branch, and a switch in an inactive branch of an include, do not.

  Positive controls (bound reads stay bound) beside every decline, and a
  no-wrong-edge check that the declined name lands on the const, not the value.
  Run from a NEUTRAL CWD, pwsh 7.
#>
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-enumscdecl-$PID"
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

Emit 'scon.inc'    '{$SCOPEDENUMS ON}'
Emit 'scoff.inc'   '{$SCOPEDENUMS OFF}'
Emit 'scnest.inc'  '{$I scon.inc}'
Emit 'scdeadin.inc' @'
{$IFDEF E14_NEVER_DEFINED}
{$SCOPEDENUMS ON}
{$ENDIF}
'@

Emit 'uScTypes.pas' @'
unit uScTypes;
interface
type
  TScPlain = (cpOne, cpTwo);
{$SCOPEDENUMS ON}
  TScScoped = (csOne, csTwo);
  TScClash = (ccOne, ccTwo);
{$SCOPEDENUMS OFF}
{$I scon.inc}
  TScInc = (ciOne, ciTwo);
{$I scoff.inc}
  TScIncOff = (coOne, coTwo);
{$IFDEF E14_NEVER_DEFINED}
{$I scon.inc}
{$ENDIF}
  TScIncDead = (cdOne, cdTwo);
{$I scnest.inc}
  TScNest = (cnOne, cnTwo);
{$SCOPEDENUMS OFF}
{$I scdeadin.inc}
  TScDeadIn = (cxOne, cxTwo);
const
  ccOne = 7;
implementation
end.
'@

# Line numbers matter: the assertions match on them.
Emit 'uScUse.pas' @'
unit uScUse;
interface
uses uScTypes;
procedure P;
implementation
procedure P;
var
  S: TScScoped; A: TScPlain; I: TScInc; N: TScNest; O: TScIncOff; D: TScIncDead; X: TScDeadIn; K: Integer;
begin
  S := csOne;
  S := TScScoped.csTwo;
  A := cpOne;
  I := ciOne;
  I := TScInc.ciTwo;
  N := cnOne;
  O := coOne;
  K := ccOne;
  D := cdOne;
  X := cxOne;
end;
end.
'@
#  10 DECLINE  bare csOne, TScScoped scoped in the host text
#  11 BIND     qualified TScScoped.csTwo
#  12 BIND     bare cpOne, TScPlain unscoped (positive control)
#  13 DECLINE  bare ciOne, scoped by scon.inc
#  14 BIND     qualified TScInc.ciTwo
#  15 DECLINE  bare cnOne, scoped by a NESTED include
#  16 BIND     bare coOne, scoff.inc switched it OFF again
#  17 BIND     bare ccOne -> the CONST uScTypes.ccOne, never the scoped value
#  18 BIND     bare cdOne, the include sits in an inactive branch
#  19 BIND     bare cxOne, the switch inside the include is in an inactive branch

$manifest = Join-Path $WorkDir 'manifest.drag-lint.json'
$mtext = '{' + [char]10 +
  '  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },' + [char]10 +
  '  "indexes": { "outDir": "out", "sections": [ { "name": "SecSc", "db": "sc.sqlite", "include": ["src"] } ] }' + [char]10 +
  '}'
[System.IO.File]::WriteAllText($manifest, $mtext, [System.Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'out\sc.sqlite'

Push-Location C:\TEMP
try {
  $idxOut = & $Exe index --all --config $manifest --only SecSc --jobs 1 2>&1 | Out-String
  if (-not (Test-Path $db)) {
    Write-Host "FATAL: index did not produce $db" -ForegroundColor Red; exit 2
  }
  $facts = & $Exe sql --db $db --query ("select name || '=' || coalesce(directives, '') from symbols " +
                                        "where kind = 'enum' order by name") 2>&1 | Out-String
  $binds = & $Exe sql --db $db --query ("select 'L' || r.start_line || '|' || r.name_text || '|' || " +
                                        "coalesce(s.kind || ':' || s.qualified_name, 'NULL') " +
                                        "from refs r join files f on f.id = r.file_id " +
                                        "left join symbols s on s.id = r.symbol_id " +
                                        "where f.path like '%uScUse.pas' and r.kind = 'read' " +
                                        "and r.start_line between 10 and 19") 2>&1 | Out-String
  $lintOut = & $Exe lint-all --db $db --quiet 2>&1 | Out-String
} finally { Pop-Location }

function FactOf([string]$type) {
  $m = [regex]::Match($facts, '(?m)^\s*' + $type + '=(\S*)\s*$')
  if ($m.Success) { $m.Groups[1].Value } else { '<missing>' }
}
function BindOf([int]$line, [string]$name) {
  $m = [regex]::Match($binds, '(?m)^\s*L' + $line + '\|' + $name + '\|(\S+)\s*$')
  if ($m.Success) { $m.Groups[1].Value } else { '<no read ref>' }
}

Write-Host ''
Write-Host 'THE FACT -- the switch is seen through include files' -ForegroundColor Cyan
Check 'TScScoped (host switch) carries scopedenums' ((FactOf 'TScScoped') -eq 'scopedenums') (FactOf 'TScScoped')
Check 'TScInc (ON from scon.inc) carries scopedenums' ((FactOf 'TScInc') -eq 'scopedenums') (FactOf 'TScInc')
Check 'TScNest (ON from a NESTED include) carries scopedenums' ((FactOf 'TScNest') -eq 'scopedenums') (FactOf 'TScNest')
Check 'NEG: TScPlain (before any switch) carries nothing' ((FactOf 'TScPlain') -eq '') (FactOf 'TScPlain')
Check 'NEG: TScIncOff (scoff.inc switched OFF) carries nothing' ((FactOf 'TScIncOff') -eq '') (FactOf 'TScIncOff')
Check 'NEG: TScIncDead (include in an inactive branch) carries nothing' ((FactOf 'TScIncDead') -eq '') (FactOf 'TScIncDead')
Check 'NEG: TScDeadIn (switch in an inactive branch of the include) carries nothing' ((FactOf 'TScDeadIn') -eq '') (FactOf 'TScDeadIn')

Write-Host ''
Write-Host 'THE DECLINE -- bare reads of scoped values stay unbound' -ForegroundColor Cyan
Check 'L10 bare csOne (host-scoped) is NOT bound' ((BindOf 10 'csOne') -eq 'NULL') (BindOf 10 'csOne')
Check 'L13 bare ciOne (include-scoped) is NOT bound' ((BindOf 13 'ciOne') -eq 'NULL') (BindOf 13 'ciOne')
Check 'L15 bare cnOne (nested-include-scoped) is NOT bound' ((BindOf 15 'cnOne') -eq 'NULL') (BindOf 15 'cnOne')

Write-Host ''
Write-Host 'POSITIVE CONTROLS -- everything else still binds' -ForegroundColor Cyan
Check 'L12 bare cpOne binds to the unscoped value' ((BindOf 12 'cpOne') -eq 'enum_value:uScTypes.TScPlain.cpOne') (BindOf 12 'cpOne')
Check 'L16 bare coOne binds (switched OFF by include)' ((BindOf 16 'coOne') -eq 'enum_value:uScTypes.TScIncOff.coOne') (BindOf 16 'coOne')
Check 'L18 bare cdOne binds (include in an inactive branch)' ((BindOf 18 'cdOne') -eq 'enum_value:uScTypes.TScIncDead.cdOne') (BindOf 18 'cdOne')
Check 'L19 bare cxOne binds (switch inactive inside the include)' ((BindOf 19 'cxOne') -eq 'enum_value:uScTypes.TScDeadIn.cxOne') (BindOf 19 'cxOne')
$q = & $Exe sql --db $db --query ("select count(*) from refs r join symbols s on s.id = r.symbol_id " +
                                  "join files f on f.id = r.file_id where f.path like '%uScUse.pas' " +
                                  "and s.qualified_name in ('uScTypes.TScScoped.csTwo', 'uScTypes.TScInc.ciTwo')") 2>&1 | Out-String
Check 'L11/L14 qualified scoped values are bound (both)' ($q -match '(?m)^\s*2\s*$') ($q.Trim() -replace '\s+', ' ')

Write-Host ''
Write-Host 'NO WRONG EDGE' -ForegroundColor Cyan
Check 'L17 bare ccOne binds to the CONST, not the scoped value' ((BindOf 17 'ccOne') -eq 'const:uScTypes.ccOne') (BindOf 17 'ccOne')
$wrong = & $Exe sql --db $db --query ("select count(*) from refs r join symbols v on v.id = r.symbol_id " +
                                      "join symbols e on e.id = v.parent_id " +
                                      "where v.kind = 'enum_value' and coalesce(r.receiver_text, '') = '' " +
                                      "and e.directives = 'scopedenums'") 2>&1 | Out-String
Check 'no bare ref anywhere is bound to a scoped value' ($wrong -match '(?m)^\s*0\s*$') ($wrong.Trim() -replace '\s+', ' ')
$evLn = (@(($idxOut -split "`r?`n") | Where-Object { $_ -match 'enum-values:' }) -join ' ')
$gotScoped = if ($evLn -match 'scoped \(bare form unreachable\) (\d+)') { [int]$Matches[1] } else { -1 }
Check 'the decline is COUNTED: scoped = 4 (L10, L13, L15, and L17 before the const pass binds it)' ($gotScoped -eq 4) ("scoped=$gotScoped line=$evLn")
Check 'enum-bare-read-scoped has nothing left to report' (-not ($lintOut -match 'enum-bare-read-scoped')) ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\drag-lint-enumscdecl-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
