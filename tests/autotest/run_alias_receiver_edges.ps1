<#
  run_alias_receiver_edges.ps1 -- member C of the extractor batch
  (docs\PLAN-extractor-batch-2026-08-30.md sec 4.3).

  THE GAP
  --------------------------------------------------------------------------------
  A member call through a plain TYPE ALIAS resolves to no call edge:

      unit uBase;   type TBase    = class procedure Ping; end;
      unit uAlias;  type TAliased = TBase;
      unit uCaller; var X: TAliased;  X.Ping;   <- 0 edges

  TryWalkAlias (DRagLint.Parser.Delphi13.pas:1097-1121) emits skTypeAlias with
  the target text as the SIGNATURE and leaves Heritage empty, so no
  type_ancestors row is ever built and CallResolver has nothing to climb.

  IT IS CROSS-LAYER, and the originating note is half wrong about that. Setting
  Heritage in the parser alone does NOTHING: ResolveAncestry builds
  type_ancestors from symbols.heritage but its SELECT filters
  WHERE kind IN ('class','interface') (Storage.SQLite.pas ~9459), which excludes
  the alias kind. The storage filter has to move too.

  WHY find-callers IS NOT ENOUGH TO PROVE THIS. FindCallersByName matches ANY
  ref kind by NAME, so it can already list the alias-typed site while the edge
  is absent -- a name match is not a resolution. The load-bearing assertions
  below are therefore on call_edges and type_ancestors, and find-callers is
  reported separately as the user-facing surface.

  THE IMPOSTOR GUARD IS THE POINT. A second unit declares an unrelated class
  with its OWN Ping. A fix that resolves by name alone would satisfy every
  "an edge exists" assertion while binding the call to the wrong method, which
  is worse than the absence it replaced. The alias-typed call must reach
  uBase.TBase.Ping and must NOT reach uImpostor.TOther.Ping.

  CENSUS (session 51, live indexes): plain aliases whose target is a known
  class/record/interface -- ORM3 CLIENT 20 of 403 'type' symbols, SERVER 2 of
  128, DragLint-Cli 3 of 57. Low, and mostly third-party C-header record
  aliases. The owner ruled KEEP anyway, so that a future alias fix never needs
  its own extractor bump and 5-hour reindex.

  NOT THIS DEFECT, do not conflate them: helper-method calls resolve to zero
  edges too (1,029 call refs on TTSNodeHelper in this repo's own index, 0
  resolved), and that is INDEPENDENT of aliasing -- a helper on a plain enum
  with no alias in the path also resolves 0. See
  docs\INBOX-helper-method-calls-resolve-to-no-edge.md. It is a resolve-pass
  gap needing no reindex, and member C must not be credited with those sites.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-alias-edges"
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

Put 'uBase.pas' @'
unit uBase;

interface

type
  TBase = class
    procedure Ping;
  end;

  TDer = class(TBase)
  end;

implementation

procedure TBase.Ping;
begin
end;

end.
'@

Put 'uImpostor.pas' @'
unit uImpostor;

interface

type
  TOther = class
    procedure Ping;
  end;

implementation

procedure TOther.Ping;
begin
end;

end.
'@

Put 'uAlias.pas' @'
unit uAlias;

interface

uses
  uBase;

type
  TAliased = TBase;

implementation

end.
'@

Put 'uCaller.pas' @'
unit uCaller;

interface

procedure CallViaAlias;
procedure CallViaInheritance;
procedure CallViaImpostor;

implementation

uses
  uBase, uAlias, uImpostor;

procedure CallViaAlias;
var
  X: TAliased;
begin
  X.Ping;
end;

procedure CallViaInheritance;
var
  D: TDer;
begin
  D.Ping;
end;

procedure CallViaImpostor;
var
  O: TOther;
begin
  O.Ping;
end;

end.
'@

$db = Join-Path $WorkDir 'alias.sqlite'
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

out['alias_to_base']       = edges('CallViaAlias', 'ubase.tbase.ping')
out['alias_conf']          = conf('CallViaAlias', 'ubase.tbase.ping')
out['alias_to_impostor']   = edges('CallViaAlias', 'uimpostor.tother.ping')
out['inherit_to_base']     = edges('CallViaInheritance', 'ubase.tbase.ping')
out['inherit_conf']        = conf('CallViaInheritance', 'ubase.tbase.ping')
out['impostor_to_own']     = edges('CallViaImpostor', 'uimpostor.tother.ping')

rows = c.execute("""
    SELECT a.ordinal, LOWER(a.ancestor_name) FROM type_ancestors a
    JOIN symbols s ON s.id = a.symbol_id
    WHERE LOWER(s.qualified_name) = 'ualias.taliased'""").fetchall()
out['alias_anc_rows']    = len(rows)
out['alias_anc_ordinal'] = rows[0][0] if rows else -1
out['alias_anc_name']    = rows[0][1] if rows else ''

out['der_anc_rows'] = c.execute("""
    SELECT COUNT(*) FROM type_ancestors a JOIN symbols s ON s.id = a.symbol_id
    WHERE LOWER(s.qualified_name) = 'ubase.tder'""").fetchone()[0]

print(json.dumps(out))
c.close()
'@ | Set-Content $py -Encoding ascii
$r = (& python $py $db) -join "`n" | ConvertFrom-Json

Write-Host 'call_edges' -ForegroundColor Cyan
Check 'HAZARD: alias-typed receiver resolves to the base method' ($r.alias_to_base -ge 1) "edges=$($r.alias_to_base)"
Check 'HAZARD: and it resolves with confidence certain' ($r.alias_conf -eq 'certain') "confidence=$($r.alias_conf)"
Check 'CONTROL: inheritance-typed receiver resolves'    ($r.inherit_to_base -ge 1) "edges=$($r.inherit_to_base)  -- green TODAY; breaking this is a restructure, not a fix"
Check 'CONTROL: and with confidence certain'            ($r.inherit_conf -eq 'certain') "confidence=$($r.inherit_conf)"
Check 'CONTROL: a direct call on an unrelated class resolves' ($r.impostor_to_own -ge 1) "edges=$($r.impostor_to_own)"

Write-Host ''
Write-Host 'IMPOSTOR GUARD -- a fix must not resolve by name alone' -ForegroundColor Cyan
Check 'the alias-typed call does NOT bind the impostor Ping' ($r.alias_to_impostor -eq 0) "edges=$($r.alias_to_impostor)"

Write-Host ''
Write-Host 'type_ancestors shape' -ForegroundColor Cyan
Check 'HAZARD: the alias has exactly ONE ancestor row' ($r.alias_anc_rows -eq 1) "rows=$($r.alias_anc_rows)"
Check 'HAZARD: at ordinal 0'                           ($r.alias_anc_ordinal -eq 0) "ordinal=$($r.alias_anc_ordinal)"
Check 'HAZARD: naming the alias target'                ($r.alias_anc_name -eq 'tbase') "ancestor_name=$($r.alias_anc_name)"
Check 'CONTROL: a real descendant still has its row'   ($r.der_anc_rows -ge 1) "rows=$($r.der_anc_rows)  -- alias rows must be purely ADDITIVE"

Write-Host ''
Write-Host 'find-callers (user-facing; a NAME match, not a resolution)' -ForegroundColor Cyan
$fc = (& $Exe query find-callers --name Ping --db $db 2>$null | Out-String)
Check 'find-callers Ping lists the alias-typed site' ($fc -match 'uCaller\.pas')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
