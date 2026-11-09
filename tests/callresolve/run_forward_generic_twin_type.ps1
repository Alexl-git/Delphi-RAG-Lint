<#
  run_forward_generic_twin_type.ps1 -- 150-RS2 (7) / 150-RB2-d: a type with a
  FORWARD declaration AND a generic twin of the same base name binds certain.

  Origin (149 RB2 150 rows, 4): ORM3 COMMON\IuMicObject.pas declares
  `IDataService = interface;` (forward, 58), `IDataService<I> = interface;` (59),
  the full IDataService (85) and the full IDataService<I> (148); LookupTypeName
  counted 4 candidates -> 443 of the 444 'ambiguous' type_use refs on CLIENT.

  CASES (markers in uUse.pas; lines are read from the fixture)
    T1 var X: IDataService           -> the FULL non-generic decl (uS.IDataService, line of `// FULL`)
    T2 X.Go                          -> call binds uS.IDataService.Go (receiver typed through T1)
    T3 Y: IDataService<IMicObject>   -> the FULL generic decl (`// FULLG`), never the forward
    T4 Z: IMicObject                 -> uS.IMicObject (forward + full, no twin)
    N1 D: TDup (two FULL decls)      -> stays unbound (positive control: a real tie still declines)

  `sql --json` rows are POSITIONAL arrays; Sql() maps them onto column names.
  Usage: pwsh -File tests\callresolve\run_forward_generic_twin_type.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_fwd_twin_$PID"
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
function W($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

W (Join-Path $WorkDir 'uS.pas') @'
unit uS;

interface

type
  IDataService = interface;
  IDataService<I> = interface;
  IMicObject = interface;

  IMicObject = interface // FULLM
    function Svc: IDataService;
  end;

  IDataService = interface // FULL
    procedure Go;
  end;

  IDataService<I> = interface(IDataService) // FULLG
    function Get: I;
  end;

  TDup = class
  end;

  TDup = class
    procedure Run;
  end;

implementation

procedure TDup.Run;
begin
end;

end.
'@
W (Join-Path $WorkDir 'uUse.pas') @'
unit uUse;

interface

uses
  uS;

procedure Work;

implementation

procedure Work;
var
  X: IDataService; // T1
  Y: IDataService<IMicObject>; // T3
  Z: IMicObject; // T4
  D: TDup; // N1
begin
  X.Go; // T2
  if (Y = nil) or (Z = nil) or (D = nil) then
    Exit;
end;

end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;

uses
  uS in 'uS.pas',
  uUse in 'uUse.pas';

begin
  Work;
end.
'@

$db = Join-Path $WorkDir 'App.sqlite'
& $Exe index --project (Join-Path $WorkDir 'App.dpr') --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

function Sql([string]$Q) {
  $j = & $Exe sql --db $db --json --limit 1000 --query $Q 2>$null | ConvertFrom-Json
  if ($null -eq $j) { return ,@() }
  $cols = @($j.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($row in $j.rows) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $row[$i] }
    $out += [pscustomobject]$o
  }
  return ,$out
}
function LineOfMarker([string]$File, [string]$Marker) {
  $ls = [IO.File]::ReadAllLines((Join-Path $WorkDir $File))
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match ('// ' + [regex]::Escape($Marker) + '$')) { return $i + 1 } }
  return -1
}
function TypeUseAt([string]$Marker, [string]$Name) {
  $ln = LineOfMarker 'uUse.pas' $Marker
  return ,(Sql ("SELECT r.id, r.symbol_id AS sid, s.qualified_name AS sq, s.start_line AS sl FROM refs r " +
                "JOIN files f ON f.id = r.file_id LEFT JOIN symbols s ON s.id = r.symbol_id " +
                "WHERE r.kind = 'type_use' AND r.name_text = '$Name' AND r.start_line = $ln AND f.path LIKE '%\uUse.pas'"))
}

$full  = LineOfMarker 'uS.pas' 'FULL'
$fullg = LineOfMarker 'uS.pas' 'FULLG'
$fullm = LineOfMarker 'uS.pas' 'FULLM'

$r = TypeUseAt 'T1' 'IDataService'
Check 'T1  var X: IDataService binds the FULL non-generic declaration' `
  (($r.Count -eq 1) -and ($r[0].sq -eq 'uS.IDataService') -and ($r[0].sl -eq $full)) ("rows=$($r.Count) sq=$($r[0].sq) sl=$($r[0].sl) want line $full")

$ln = LineOfMarker 'uUse.pas' 'T2'
$r = Sql ("SELECT t.qualified_name AS tq, ce.confidence AS cf FROM refs r JOIN files f ON f.id = r.file_id " +
          "LEFT JOIN call_edges ce ON ce.ref_id = r.id LEFT JOIN symbols t ON t.id = ce.target_symbol_id " +
          "WHERE r.kind = 'call' AND r.name_text = 'Go' AND r.start_line = $ln AND f.path LIKE '%\uUse.pas'")
Check 'T2  X.Go binds uS.IDataService.Go' `
  (($r.Count -eq 1) -and ($r[0].tq -eq 'uS.IDataService.Go')) ("rows=$($r.Count) tq=$($r[0].tq) cf=$($r[0].cf)")

$r = TypeUseAt 'T3' 'IDataService'
Check 'T3  Y: IDataService<IMicObject> binds the FULL generic declaration' `
  (($r.Count -eq 1) -and ($r[0].sl -eq $fullg)) ("rows=$($r.Count) sq=$($r[0].sq) sl=$($r[0].sl) want line $fullg")

$r = TypeUseAt 'T4' 'IMicObject'
Check 'T4  Z: IMicObject binds the FULL declaration over its forward' `
  (($r.Count -eq 1) -and ($r[0].sl -eq $fullm)) ("rows=$($r.Count) sq=$($r[0].sq) sl=$($r[0].sl) want line $fullm")

$r = TypeUseAt 'N1' 'TDup'
Check 'N1  D: TDup (two FULL decls) stays unbound -- positive control' `
  (($r.Count -eq 1) -and ($null -eq $r[0].sid)) ("rows=$($r.Count) sq=$($r[0].sq) sl=$($r[0].sl)")

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} catch {
  Write-Host "FATAL: $_" -ForegroundColor Red
  exit 2
}
