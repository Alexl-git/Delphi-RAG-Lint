<#
  run_library_type_uses_order_bind.ps1 -- a receiver declared with a LIBRARY
  type name two used units both export binds the way the compiler reads it: the
  unit used LAST wins, and implementation uses are not visible to an interface
  declaration.

  Wave 150 RS1 item (5) (149 RB2 "150-RB2-c": `BBitmap.Free`, TBitmap from
  Vcl.Graphics AND Winapi.Windows; TLibraryOracle.Pick saw two visible
  candidates and declined). Fix: the field / local rung records the declaration
  (TRcvTypeText.DeclFile / DeclLine); BindExternally hands the oracle the uses
  visible there (System, SysInit, interface uses, implementation uses before the
  declaration, in source order -- TLibraryOracle.DeclUses), and Pick decides an
  own-uses tie by the LAST of them. A text without generic arguments then names
  only a non-generic type (`FPlain: TList` is System.Classes.TList).

  CASES (markers in the fixtures; lines are read from them)
    B1 uA  uses .., Winapi.Windows, Vcl.Graphics; local BBitmap: TBitmap; BBitmap.Free   -> System.TObject.Free (Vcl.Graphics class)
    B5 uA  BBitmap.Canvas                                                                 -> Vcl.Graphics.TBitmap.Canvas
    B6 uA  BBitmap.Canvas.Lock (a CHAIN: the head's declaration rides with the pending step, found-in-150) -> Vcl.Graphics.TCustomCanvas.Lock
    G3 uA  uses System.Classes, System.Generics.Collections; FPlain: TList; FPlain.Add   -> System.Classes.TList.Add
    B2 uB  uses Vcl.Graphics, Winapi.Windows; local B: TBitmap; B.bmWidth                 -> Winapi.Windows.tagBITMAP.bmWidth
    B3 uC  interface uses Vcl.Graphics; implementation uses Winapi.Windows;
           FBmp: TBitmap declared in the INTERFACE: FBmp.Free                             -> System.TObject.Free (Vcl.Graphics)
    B4 uC  local L: TBitmap in the implementation: L.bmWidth                             -> Winapi.Windows.tagBITMAP.bmWidth
  B2 / B4 are the mirror of B1 / B3: the same name picks the OTHER unit when the
  order or the section flips, so no fixed preference can pass all six.

  Needs the platform library C:\Projects\.drag-lint\library-Win64.sqlite (READ
  only). Missing library = FATAL, never a skip.
  RED on 1.49.0-alpha (150 base): every case external_target NULL.
  Usage: pwsh -File tests\callresolve\run_library_type_uses_order_bind.ps1 [-Exe <drag-lint.exe>] [-LibraryDb <db>]
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$LibraryDb = "C:\Projects\.drag-lint\library-Win64.sqlite",
  [string]$WorkDir   = "C:\TEMP\draglint_lib_usesorder_$PID"
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

W (Join-Path $WorkDir 'uA.pas') @'
unit uA;

interface

uses
  System.Classes, System.Generics.Collections, Winapi.Windows, Vcl.Graphics;

type
  THost = class
  public
    FPlain: TList;
    procedure Run;
  end;

implementation

procedure THost.Run;
var
  BBitmap: TBitmap;
begin
  FPlain.Add(nil); // G3
  BBitmap.Free; // B1
  BBitmap.Canvas.Lock; // B5
end;

end.
'@
W (Join-Path $WorkDir 'uB.pas') @'
unit uB;

interface

uses
  Vcl.Graphics, Winapi.Windows;

procedure RunB;

implementation

procedure RunB;
var
  B: TBitmap;
begin
  B.bmWidth := 1; // B2
end;

end.
'@
W (Join-Path $WorkDir 'uC.pas') @'
unit uC;

interface

uses
  Vcl.Graphics;

type
  TC = class
  public
    FBmp: TBitmap;
    procedure Run;
  end;

implementation

uses
  Winapi.Windows;

procedure TC.Run;
var
  L: TBitmap;
begin
  FBmp.Free; // B3
  L.bmWidth := 1; // B4
end;

end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;

uses
  uA in 'uA.pas',
  uB in 'uB.pas',
  uC in 'uC.pas';

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
# Every call / member-access ref named AName on the marker line of AFile, with its external_target.
function ExtAt([string]$AFile, [string]$Marker, [string]$AName) {
  $ln = LineOfMarker $AFile $Marker
  $q = "SELECT r.kind, r.external_target AS ext, r.receiver_text AS rcv FROM refs r JOIN files f ON f.id = r.file_id " +
       "WHERE r.kind IN ('call', 'member-access') AND r.name_text = '$AName' AND r.start_line = $ln AND f.path LIKE '%\$AFile'"
  return ,(Sql $q)
}
function Expect([string]$Label, [string]$AFile, [string]$Marker, [string]$AName, [string]$Ext) {
  $r = ExtAt $AFile $Marker $AName
  $ok = ($r.Count -ge 1) -and (@($r | Where-Object { $_.ext -ne $Ext }).Count -eq 0)
  Check $Label $ok ("rows=$($r.Count) " + (($r | ForEach-Object { "[$($_.kind) rcv=$($_.rcv) ext=$($_.ext)]" }) -join ' '))
}

Expect 'B1  uA (Windows, Graphics) BBitmap.Free: System.TObject.Free'          'uA.pas' 'B1' 'Free'    'System.TObject.Free'
Expect 'B5  uA BBitmap.Canvas: Vcl.Graphics.TBitmap.Canvas'                     'uA.pas' 'B5' 'Canvas'  'Vcl.Graphics.TBitmap.Canvas'
Expect 'B6  uA BBitmap.Canvas.Lock (chain head, pending step): Vcl.Graphics.TCustomCanvas.Lock' 'uA.pas' 'B5' 'Lock' 'Vcl.Graphics.TCustomCanvas.Lock'
Expect 'G3  uA FPlain: TList (no generic args): System.Classes.TList.Add'       'uA.pas' 'G3' 'Add'     'System.Classes.TList.Add'
Expect 'B2  uB (Graphics, Windows) B.bmWidth: Winapi.Windows.tagBITMAP.bmWidth' 'uB.pas' 'B2' 'bmWidth' 'Winapi.Windows.tagBITMAP.bmWidth'
Expect 'B3  uC interface field FBmp (impl uses not visible): System.TObject.Free' 'uC.pas' 'B3' 'Free'   'System.TObject.Free'
Expect 'B4  uC implementation local L: Winapi.Windows.tagBITMAP.bmWidth'        'uC.pas' 'B4' 'bmWidth' 'Winapi.Windows.tagBITMAP.bmWidth'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_lib_usesorder_$PID")) { if (Test-Path -LiteralPath $d23) { [IO.Directory]::Delete($d23, $true) } }
}
