<#
  run_helper_method_edges.ps1 -- a call to a method declared on a record/type
  HELPER must resolve to a call edge.

  THE GAP (docs/INBOX-helper-method-calls-resolve-to-no-edge.md)
  --------------------------------------------------------------------------------
  TCallResolver never consults `type_helpers` AT ALL -- grep the unit, there is
  not one reference to it. So a call on a helper method produces a `call` ref and
  NO edge, and find-callers on that method answers "nothing calls this", which is
  the dangerous direction for this tool to be wrong in.

  MEASURED before the fix (live indexes, extractor 1.8.0-alpha):

      DragLint-Cli   1,029 helper-member call refs ->     0 resolved
      ORM3 CLIENT    1,644                          ->    18 (1.1%)
      ORM3 SERVER    1,745                          ->    18 (1.0%)

  `ChildByField` alone: 523 call refs in this repo's own index, 0 resolved.

  IT IS NOT THE ALIAS DEFECT, and that matters because it looked exactly like it.
  The highest-count helper target in this repo (TTSNode) IS an alias, so the
  numbers above were briefly attributed to the alias-typed-receiver gap. The
  control refutes it: TSymbolKindHelper helps a plain ENUM with no alias anywhere
  in the path and also resolves 0 of 5. That is why case 1 below uses a plain
  record -- no alias in sight -- and case 2 tests the alias path SEPARATELY.

  THE TWO ARE COUPLED, which case 2 pins. Extractor 1.9.0-alpha made alias-typed
  receivers resolve, and it produced ZERO new edges on three corpora precisely
  because the aliases people actually call methods through are helper-backed.
  Neither fix pays alone.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-helper-edges"
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Put($name, $text) {
  $t = $text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText((Join-Path $WorkDir $name), $t, [System.Text.Encoding]::ASCII)
}

Put 'uBaseH.pas' @'
unit uBaseH;

interface

type
  TWidget = record
    Value: Integer;
  end;

  TAliasW = TWidget;

  { Enum helpers are a everyday Delphi idiom (TMyEnum.ToString), and on ORM3
    CLIENT 16 of 22 helper targets are enums. }
  TMood = (moCalm, moCross);

implementation

end.
'@

Put 'uHelperH.pas' @'
unit uHelperH;

interface

uses
  uBaseH;

type
  TWidgetHelper = record helper for TWidget
    procedure Poke;
  end;

  TMoodHelper = record helper for TMood
    function Describe: string;
  end;

implementation

procedure TWidgetHelper.Poke;
begin
end;

function TMoodHelper.Describe: string;
begin
  result:= '';
end;

end.
'@

Put 'uImpostorH.pas' @'
unit uImpostorH;

interface

type
  TOtherThing = class
    procedure Poke;
    procedure OrdinaryCall;
  end;

implementation

procedure TOtherThing.Poke;
begin
end;

procedure TOtherThing.OrdinaryCall;
begin
end;

end.
'@

Put 'uCallerH.pas' @'
unit uCallerH;

interface

procedure CallViaHelper;
procedure CallViaAliasHelper;
procedure CallOrdinaryMethod;
procedure CallViaEnumHelper;

implementation

uses
  uBaseH, uHelperH, uImpostorH;

procedure CallViaHelper;
var
  W: TWidget;
begin
  W.Poke;
end;

procedure CallViaAliasHelper;
var
  X: TAliasW;
begin
  X.Poke;
end;

procedure CallOrdinaryMethod;
var
  O: TOtherThing;
begin
  O.OrdinaryCall;
end;

procedure CallViaEnumHelper;
var
  M: TMood;
begin
  M.Describe;
end;

end.
'@

$db = Join-Path $WorkDir 'helper.sqlite'
& $Exe index $WorkDir --db $db --quiet 2>&1 | Out-Null

$py = Join-Path $WorkDir 'edges.py'
@'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
out = {}

def edges(caller, target):
    return c.execute("""
        SELECT COUNT(*) FROM call_edges e
        JOIN refs r     ON r.id = e.ref_id
        JOIN symbols en ON en.id = r.enclosing_symbol_id
        JOIN symbols t  ON t.id = e.target_symbol_id
        WHERE en.name LIKE ? COLLATE NOCASE
          AND LOWER(t.qualified_name) = ?""", (caller, target)).fetchone()[0]

def conf(caller, target):
    row = c.execute("""
        SELECT e.confidence FROM call_edges e
        JOIN refs r     ON r.id = e.ref_id
        JOIN symbols en ON en.id = r.enclosing_symbol_id
        JOIN symbols t  ON t.id = e.target_symbol_id
        WHERE en.name LIKE ? COLLATE NOCASE
          AND LOWER(t.qualified_name) = ?""", (caller, target)).fetchone()
    return row[0] if row else ''

HELPER  = 'uhelperh.twidgethelper.poke'
IMPOST  = 'uimpostorh.totherthing.poke'
ORDIN   = 'uimpostorh.totherthing.ordinarycall'

out['plain_to_helper']    = edges('CallViaHelper', HELPER)
out['plain_conf']         = conf('CallViaHelper', HELPER)
out['plain_to_impostor']  = edges('CallViaHelper', IMPOST)
out['alias_to_helper']    = edges('CallViaAliasHelper', HELPER)
out['alias_to_impostor']  = edges('CallViaAliasHelper', IMPOST)
out['ordinary_resolves']  = edges('CallOrdinaryMethod', ORDIN)
out['enum_to_helper']     = edges('CallViaEnumHelper', 'uhelperh.tmoodhelper.describe')
out['ordinary_conf']      = conf('CallOrdinaryMethod', ORDIN)

out['helper_rows'] = c.execute("SELECT COUNT(*) FROM type_helpers").fetchone()[0]
print(json.dumps(out))
c.close()
'@ | Set-Content $py -Encoding ascii
$r = (& python $py $db) -join "`n" | ConvertFrom-Json

Write-Host 'The index already HAS the helper data' -ForegroundColor Cyan
Check 'CONTROL: type_helpers is populated' ($r.helper_rows -ge 1) "rows=$($r.helper_rows)  -- so this is a RESOLVER gap, not an extraction one"

Write-Host ''
Write-Host 'Case 1 -- helper on a PLAIN record (no alias anywhere)' -ForegroundColor Cyan
Check 'HAZARD: W.Poke resolves to the helper method' ($r.plain_to_helper -ge 1) "edges=$($r.plain_to_helper)"
Check 'HAZARD: and with confidence certain'          ($r.plain_conf -eq 'certain') "confidence=$($r.plain_conf)"

Write-Host ''
Write-Host 'Case 2 -- helper reached THROUGH an alias (the coupling with member C)' -ForegroundColor Cyan
Check 'HAZARD: X.Poke on an alias-typed receiver resolves' ($r.alias_to_helper -ge 1) "edges=$($r.alias_to_helper)  -- needs BOTH the alias ancestor row and the helper lookup"

Write-Host ''
Write-Host 'Case 3 -- helper on an ENUM (16 of 22 helper targets on ORM3 CLIENT)' -ForegroundColor Cyan
Check 'HAZARD: M.Describe on an enum-typed receiver resolves' ($r.enum_to_helper -ge 1) "edges=$($r.enum_to_helper)  -- an enum-typed receiver could not be TYPED at all, so the helper was never consulted"

Write-Host ''
Write-Host 'IMPOSTOR GUARD -- a fix must not resolve by name alone' -ForegroundColor Cyan
Check 'the plain-record call does NOT bind the impostor Poke' ($r.plain_to_impostor -eq 0) "edges=$($r.plain_to_impostor)"
Check 'the alias-typed call does NOT bind the impostor Poke'  ($r.alias_to_impostor -eq 0) "edges=$($r.alias_to_impostor)"

Write-Host ''
Write-Host 'CONTROL -- ordinary method resolution is untouched' -ForegroundColor Cyan
Check 'a non-helper method call still resolves' ($r.ordinary_resolves -ge 1) "edges=$($r.ordinary_resolves)  -- green TODAY; breaking this is a restructure, not a fix"
Check 'and still with confidence certain'       ($r.ordinary_conf -eq 'certain') "confidence=$($r.ordinary_conf)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
