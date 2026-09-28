<#
  run_purity_unit_qualified_write.ps1 -- a write to a unit-level var spelled
  through its unit (`uVars.GFlag := True`) is a GLOBAL write in the purity
  verdict, exactly as the same write spelled bare.

  THE DEFECT (BACKLOG-TRIAGE-2026-09-28 FIX-3, part 1). Since D22 (resolver
  1.9.0) the unit-qualified write binds as a member-access with mode write. The
  purity stage sent every bound member write to MemberWrite, which classifies
  the RECEIVER -- Self, a field, a parameter or a local -- and a unit name is
  none of those, so the routine scored '?' "receiver not classified" (UNKNOWN)
  while `GFlag := True` scored 'g'. Two spellings of one statement, two
  verdicts; and '?' is the "binding gap" answer purity v2 exists to avoid
  reporting as a fact.

  CASES
    T1 SetQualified  uVars.GFlag := True   -> effect_free 0, summary 'g'
    C1 SetBare       GFlag := True         -> 'g' (the control: same verdict)
    C2 ReadQualified Result := uVars.GFlag -> effect_free 1 (a read is no effect)
    C3 SetField      Obj.FField := 1 on a LOCAL object -> still not 'g' (the
                     unit-level test did not swallow ordinary member writes)

  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_purity_unitq_write_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function W($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Path $WorkDir | Out-Null
W (Join-Path $WorkDir 'uVars.pas') @'
unit uVars;

interface

type
  TBox = class
  public
    FField: Integer;
  end;

var
  GFlag: Boolean;

implementation

end.
'@
W (Join-Path $WorkDir 'uUse.pas') @'
unit uUse;

interface

procedure SetQualified;
procedure SetBare;
function ReadQualified: Boolean;
procedure SetField;

implementation

uses uVars;

procedure SetQualified;
begin
  uVars.GFlag := True;
end;

procedure SetBare;
begin
  GFlag := True;
end;

function ReadQualified: Boolean;
begin
  Result := uVars.GFlag;
end;

procedure SetField;
var
  Obj: TBox;
begin
  Obj := TBox.Create;
  try
    Obj.FField := 1;
  finally
    Obj.Free;
  end;
end;

end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;
uses
  uVars in 'uVars.pas',
  uUse in 'uUse.pas';
begin
end.
'@
$db = Join-Path $WorkDir 'App.sqlite'
& $exePath index --project (Join-Path $WorkDir 'App.dpr') --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

$j = & $exePath sql --db $db --json --query "SELECT s.name, f.effect_free, f.effect_summary, f.effect_witness FROM symbols s JOIN symbol_facts f ON f.symbol_id = s.id WHERE s.name IN ('SetQualified','SetBare','ReadQualified','SetField')" 2>$null | ConvertFrom-Json
$rows = @{}
foreach ($r in $j.rows) { $rows[[string]$r[0]] = [pscustomobject]@{ Free = $r[1]; Sum = [string]$r[2]; Why = [string]$r[3] } }
Check 'V all four routines carry a purity verdict' ($rows.Count -eq 4) ($rows.Keys -join ', ')

$q = $rows['SetQualified']
Check "T1 uVars.GFlag := True scores a GLOBAL write (summary '$($q.Sum)')" (($q.Free -eq 0) -and ($q.Sum -eq 'g')) $q.Why
Check 'T1b and names the unit-level write in its witness' ($q.Why -match 'uVars\.GFlag') $q.Why
$b = $rows['SetBare']
Check "C1 CONTROL the bare spelling scores the same 'g' (summary '$($b.Sum)')" (($b.Free -eq 0) -and ($b.Sum -eq 'g')) $b.Why
$r = $rows['ReadQualified']
Check "C2 CONTROL a unit-qualified READ is no effect (effect_free $($r.Free))" ($r.Free -eq 1) $r.Why
$f = $rows['SetField']
Check "C3 CONTROL a member write on a LOCAL object is not scored global (summary '$($f.Sum)')" ($f.Sum -notmatch 'g') $f.Why

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("C:\TEMP\draglint_purity_unitq_write_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
