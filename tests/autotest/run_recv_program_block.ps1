<#
  run_recv_program_block.ps1 -- spec 2026-11-06-recv-undecidable, wave-146 b7 leftover:
  a dotted call in a PROGRAM's main block (`Application.Initialize` in the .dpr) has no
  enclosing routine, so receiver typing gave up before it offered the head to the library
  oracle, and the call stayed unbound although the same call in a unit binds.

  Pins: App.dpr `Application.Initialize` / `Application.Run` -> Vcl.Forms.TApplication.*;
  the same call in a unit still binds (control); a program whose OWN unit declares a
  unit-level `MyApp` value is not answered from the library (BindExternally's project-name
  guard); an unknown head stays unbound.
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_recv_program_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function W($dir,$name,$t){ [IO.File]::WriteAllText((Join-Path $dir $name), (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$lib = Join-Path $WorkDir 'lib'; $app = Join-Path $WorkDir 'app'
New-Item -ItemType Directory -Path $lib,$app | Out-Null

W $lib 'System.pas' @'
unit System;
interface
type
  TObject = class
  end;
implementation
end.
'@
W $lib 'Vcl.Forms.pas' @'
unit Vcl.Forms;
interface
type
  TApplication = class(TObject)
  public
    procedure Initialize;
    procedure Run;
  end;
var
  Application: TApplication;
  MyApp: TApplication;
implementation
procedure TApplication.Initialize; begin end;
procedure TApplication.Run; begin end;
end.
'@
W $app 'uA.pas' @'
unit uA;
interface
uses Vcl.Forms;
type
  TMine = class
  public
    procedure Run;
  end;
var
  MyApp: TMine;
procedure Go;
implementation
procedure TMine.Run; begin end;
procedure Go;
begin
  Application.Run;
end;
end.
'@
W $app 'App.dpr' @'
program App;

uses
  Vcl.Forms,
  uA in 'uA.pas';

begin
  Application.Initialize;
  Application.Run;
  MyApp.Run;
  NoSuchHead.Run;
end.
'@

$libDb = Join-Path $WorkDir 'lib.sqlite'; $appDb = Join-Path $WorkDir 'app.sqlite'
Push-Location C:\TEMP
& $exePath index $lib --db $libDb 2>&1 | Out-Null
Check 'V library index built' (Test-Path $libDb) $libDb
& $exePath index --project (Join-Path $app 'App.dpr') --db $appDb --library-db $libDb 2>&1 | Out-Null
Check 'V app index built' (Test-Path $appDb) $appDb
$j = & $exePath sql --db $appDb --json --limit 2000 --query "SELECT '' p, f.path, r.receiver_text, r.name_text, coalesce(r.external_target,''), coalesce(t.qualified_name,'') FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN call_edges c ON c.ref_id = r.id LEFT JOIN symbols t ON t.id = c.target_symbol_id WHERE r.kind = 'call' AND r.receiver_text <> ''" | Out-String | ConvertFrom-Json
Pop-Location

$rows = foreach ($r in $j.rows) { [pscustomobject]@{ File=[IO.Path]::GetFileName([string]$r[1]); Rcv=[string]$r[2]; Name=[string]$r[3]; Ext=[string]$r[4]; Edge=[string]$r[5] } }
Check "V the sites were read ($(@($rows).Count))" (@($rows).Count -ge 5)
function Site($file,$rcv,$name){ @($rows | Where-Object { $_.File -eq $file -and $_.Rcv -eq $rcv -and $_.Name -eq $name }) | Select-Object -First 1 }
function Ext($id,$file,$rcv,$name,$want){
  $s = Site $file $rcv $name
  Check "$id $file $rcv.$name -> external $want (got ext='$($s.Ext)' edge='$($s.Edge)')" ($null -ne $s -and $s.Ext -ceq $want)
}
function NoExt($id,$file,$rcv,$name){
  $s = Site $file $rcv $name
  Check "$id CONTROL $file $rcv.$name gets no library name (got ext='$($s.Ext)' edge='$($s.Edge)')" ($null -ne $s -and $s.Ext -eq '')
}
Ext   'P1' 'App.dpr' 'Application' 'Initialize' 'Vcl.Forms.TApplication.Initialize'
Ext   'P2' 'App.dpr' 'Application' 'Run'        'Vcl.Forms.TApplication.Run'
Ext   'P3' 'uA.pas'  'Application' 'Run'        'Vcl.Forms.TApplication.Run'
NoExt 'P4' 'App.dpr' 'MyApp'       'Run'
NoExt 'P5' 'App.dpr' 'NoSuchHead'  'Run'

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath "C:\TEMP\draglint_recv_program_$PID") { [IO.Directory]::Delete("C:\TEMP\draglint_recv_program_$PID", $true) }
}
