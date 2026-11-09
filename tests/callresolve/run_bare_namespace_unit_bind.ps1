<#
  run_bare_namespace_unit_bind.ps1 -- a BARE uses entry (`uses Forms`) is read
  through the project's unit scope names (DCC_Namespace) when the library oracle
  binds: in a VCL project `Forms` is Vcl.Forms, never FMX.Forms.

  Wave 150 RS1 item (4) (149 RB1 item 3c / 146 b7 "bare Forms"): both Vcl.Forms
  and FMX.Forms end in `.forms`, so TLibraryOracle.Pick counted two visible
  candidates for TForm / Application and declined. Fix: the resolver reads the
  project's DCC_Namespace list (from the .dproj beside the .dpr until EX3's
  stored project fact is merged) into TLibraryOracle.Namespaces; Pick does not
  count a candidate reached through a bare entry under a prefix the list does
  not name.

  CASES (markers in the fixture; lines are read from it)
    F1 F.Show                     F: TForm, `uses Forms`, namespace Vcl -> Vcl.Forms.TCustomForm.Show
    F2 Application.ProcessMessages  head value from Vcl.Forms           -> Vcl.Forms.TApplication.ProcessMessages
    Q1 S.Add('a')                 S: TStringList, `uses Classes` (only System.Classes ends in .classes)
                                  -> System.Classes.TStringList.Add (positive control: bound on the base)
  NEGATIVE CONTROL: the same fixture indexed through a .dproj with NO
  DCC_Namespace leaves F1 / F2 unbound (the tie is real; nothing guesses).

  Needs the platform library C:\Projects\.drag-lint\library-Win64.sqlite (READ
  only). Missing library = FATAL, never a skip.
  RED on 1.49.0-alpha (150 base): F1 / F2 external_target NULL.
  Usage: pwsh -File tests\callresolve\run_bare_namespace_unit_bind.ps1 [-Exe <drag-lint.exe>] [-LibraryDb <db>]
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$LibraryDb = "C:\Projects\.drag-lint\library-Win64.sqlite",
  [string]$WorkDir   = "C:\TEMP\draglint_bare_ns_$PID"
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

$unit = @'
unit uF;

interface

uses
  Forms, Classes;

procedure Run(F: TForm; S: TStringList);

implementation

procedure Run(F: TForm; S: TStringList);
begin
  F.Show; // F1
  Application.ProcessMessages; // F2
  S.Add('a'); // Q1
end;

end.
'@
$dproj = @'
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <MainSource>App.dpr</MainSource>
  </PropertyGroup>
  <PropertyGroup Condition="'$(Base)'!=''">
    __NS__
  </PropertyGroup>
  <ItemGroup>
    <DelphiCompile Include="$(MainSource)">
      <MainSource>MainSource</MainSource>
    </DelphiCompile>
    <DCCReference Include="uF.pas"/>
  </ItemGroup>
</Project>
'@
$dpr = @'
program App;

uses
  uF in 'uF.pas';

begin
end.
'@

function Sql([string]$Db, [string]$Q) {
  $j = & $Exe sql --db $Db --json --limit 1000 --query $Q 2>$null | ConvertFrom-Json
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
# Builds one project folder; ANs = the DCC_Namespace element text or '' for none. Returns the DB path.
function Build([string]$Name, [string]$ANs) {
  $d = Join-Path $WorkDir $Name
  New-Item -ItemType Directory $d | Out-Null
  W (Join-Path $d 'uF.pas') $unit
  W (Join-Path $d 'App.dpr') $dpr
  W (Join-Path $d 'App.dproj') ($dproj.Replace('__NS__', $(if ($ANs) { "<DCC_Namespace>$ANs</DCC_Namespace>" } else { '' })))
  $db = Join-Path $d 'App.sqlite'
  & $Exe index --project (Join-Path $d 'App.dproj') --db $db --library-db $LibraryDb 2>&1 | Out-Null
  return $db
}
function LineOfMarker([string]$Marker) {
  $ls = $unit -split "`r?`n"
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match ('// ' + [regex]::Escape($Marker) + '$')) { return $i + 1 } }
  return -1
}
function ExtAt([string]$Db, [string]$Marker, [string]$AName) {
  $ln = LineOfMarker $Marker
  $q = "SELECT r.kind, r.external_target AS ext FROM refs r JOIN files f ON f.id = r.file_id " +
       "WHERE r.kind IN ('call', 'member-access') AND r.name_text = '$AName' AND r.start_line = $ln AND f.path LIKE '%\uF.pas'"
  return ,(Sql $Db $q)
}
function Show($r) { return "rows=$($r.Count) " + (($r | ForEach-Object { "[$($_.kind) ext=$($_.ext)]" }) -join ' ') }
function AllExt($r, [string]$Ext) { return ($r.Count -ge 1) -and (@($r | Where-Object { $_.ext -ne $Ext }).Count -eq 0) }

$vcl = Build 'vcl' 'System;Xml;Data;Vcl;Vcl.Imaging;Winapi;$(DCC_Namespace)'
Check 'V the VCL fixture index was built' (Test-Path $vcl) $vcl
$r = ExtAt $vcl 'Q1' 'Add'
Check 'Q1  S.Add (uses Classes, one candidate): System.Classes.TStringList.Add (positive control)' (AllExt $r 'System.Classes.TStringList.Add') (Show $r)
$r = ExtAt $vcl 'F1' 'Show'
Check 'F1  F.Show (uses Forms, namespace Vcl): Vcl.Forms.TCustomForm.Show' (AllExt $r 'Vcl.Forms.TCustomForm.Show') (Show $r)
$r = ExtAt $vcl 'F2' 'ProcessMessages'
Check 'F2  Application.ProcessMessages: Vcl.Forms.TApplication.ProcessMessages' (AllExt $r 'Vcl.Forms.TApplication.ProcessMessages') (Show $r)

# S1 (150 INT, RS1 handover): the resolver reads the STORED project fact (EX3 project_settings),
# not the .dproj text. Strip the namespaces from the .dproj on disk and re-resolve from the
# stored parses: F1 must stay bound. RED on a build that still reads the .dproj text.
$vd = Split-Path $vcl
W (Join-Path $vd 'App.dproj') ($dproj.Replace('__NS__', ''))
& $Exe index --project (Join-Path $vd 'App.dproj') --db $vcl --resolve-only --library-db $LibraryDb 2>&1 | Out-Null
$r = ExtAt $vcl 'F1' 'Show'
Check 'S1  .dproj namespaces removed after the index, --resolve-only: F.Show still Vcl.Forms (stored DCC_Namespace fact)' (AllExt $r 'Vcl.Forms.TCustomForm.Show') (Show $r)

$none = Build 'none' ''
$r = ExtAt $none 'F1' 'Show'
Check 'N1  no DCC_Namespace: F.Show stays unbound (negative control -- the tie is real)' (($r.Count -ge 1) -and (@($r | Where-Object { $_.ext }).Count -eq 0)) (Show $r)

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_bare_ns_$PID")) { if (Test-Path -LiteralPath $d23) { [IO.Directory]::Delete($d23, $true) } }
}
