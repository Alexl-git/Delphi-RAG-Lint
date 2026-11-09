<#
  run_library_generic_receiver_bind.ps1 -- a receiver declared with a GENERIC
  library type (`FBinders: TList<TBinder>`) binds to the generic declaration.

  Wave 150 RS1 item (2) (149 EX1 item 6, D14 on ORM3 CLIENT WarningFlags.pas:
  `FBinders: TList<TBinder>`; FBinders.Add unbound x3). The receiver typing kept
  only the leaf `TList`, and the library oracle then saw System.Classes.TList and
  System.Generics.Collections.TList<T> -- both used -> ambiguous, no external
  target. Fix: the field / local rung hands the generic argument group to the
  oracle (TRcvTypeText.Args, never written to receiver_type_text), and
  TLibraryOracle.PickType keeps only declarations of that generic arity.

  CASES (markers in the fixture; lines are read from it)
    G1 FBinders.Add(nil)    field  TList<TBinder>           -> System.Generics.Collections.TList.Add
    G2 LBinders.Add(nil)    local  TList<TBinder>           -> System.Generics.Collections.TList.Add
    G4 FDict.Add('a', nil)  field  TDictionary<string, ..>  -> ...TDictionary.Add (positive control: bound on the base)
    receiver_type_text stays the leaf 'TList' (the stored text does not change).

  Needs the platform library C:\Projects\.drag-lint\library-Win64.sqlite (READ
  only). Missing library = FATAL, never a skip.
  RED on 1.49.0-alpha (150 base): G1 / G2 external_target NULL.
  Usage: pwsh -File tests\callresolve\run_library_generic_receiver_bind.ps1 [-Exe <drag-lint.exe>] [-LibraryDb <db>]
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$LibraryDb = "C:\Projects\.drag-lint\library-Win64.sqlite",
  [string]$WorkDir   = "C:\TEMP\draglint_lib_generic_$PID"
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
if (-not (Test-Path $LibraryDb)) { Write-Host "FATAL: library not found: $LibraryDb" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

W (Join-Path $WorkDir 'uG.pas') @'
unit uG;

interface

uses
  System.Classes, System.Generics.Collections;

type
  TBinder = class
  public
    procedure Go;
  end;

  THost = class
  public
    FBinders: TList<TBinder>;
    FDict: TDictionary<string, TBinder>;
    procedure Run;
  end;

implementation

procedure TBinder.Go;
begin
end;

procedure THost.Run;
var
  LBinders: TList<TBinder>;
begin
  FBinders.Add(nil); // G1
  LBinders.Add(nil); // G2
  FDict.Add('a', nil); // G4
end;

end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;

uses
  uG in 'uG.pas';

begin
end.
'@

$db = Join-Path $WorkDir 'App.sqlite'
& $Exe index --project (Join-Path $WorkDir 'App.dpr') --db $db --library-db $LibraryDb 2>&1 | Out-Null
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
# Every call / member-access ref named AName on the marker line: external_target + receiver_type_text.
function ExtAt([string]$Marker, [string]$AName) {
  $ln = LineOfMarker 'uG.pas' $Marker
  $q = "SELECT r.kind, r.external_target AS ext, r.receiver_type_text AS rt FROM refs r JOIN files f ON f.id = r.file_id " +
       "WHERE r.kind IN ('call', 'member-access') AND r.name_text = '$AName' AND r.start_line = $ln AND f.path LIKE '%\uG.pas'"
  return ,(Sql $q)
}
function AllExt($r, [string]$Ext) { return ($r.Count -ge 1) -and (@($r | Where-Object { $_.ext -ne $Ext }).Count -eq 0) }
function Show($r) { return "rows=$($r.Count) " + (($r | ForEach-Object { "[$($_.kind) ext=$($_.ext) rt=$($_.rt)]" }) -join ' ') }

$r = ExtAt 'G4' 'Add'
Check 'G4  FDict.Add: System.Generics.Collections.TDictionary.Add (positive control)' (AllExt $r 'System.Generics.Collections.TDictionary.Add') (Show $r)
$r = ExtAt 'G1' 'Add'
Check 'G1  FBinders.Add (field TList<TBinder>): System.Generics.Collections.TList.Add' (AllExt $r 'System.Generics.Collections.TList.Add') (Show $r)
Check 'G1  receiver_type_text stays the leaf TList' (($r.Count -ge 1) -and (@($r | Where-Object { $_.rt -ne 'TList' }).Count -eq 0)) (Show $r)
$r = ExtAt 'G2' 'Add'
Check 'G2  LBinders.Add (local TList<TBinder>): System.Generics.Collections.TList.Add' (AllExt $r 'System.Generics.Collections.TList.Add') (Show $r)

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_lib_generic_$PID")) { if (Test-Path -LiteralPath $d23) { [IO.Directory]::Delete($d23, $true) } }
}
