<#
  run_library_cast_receiver_bind.ps1 -- a member read / written through a HARD
  CAST to a LIBRARY class (`TEdit(FControls[i]).Text`) binds to the library
  member, and a rename of a project member of the same name proves past it.

  Wave 150 RS1 item (3) (149 EX1 item 4: YADF.OptionsFrame.pas:1307/1328, four
  `receiver-untyped` refusals in `rename --plan`). Measured on the 150 base:
  the cast rung already names the cast type (receiver_type_text 'TEdit') and the
  library oracle binds Text when the index is resolved WITH the platform
  library; the YADF refusals came from YADFOT / YADFSetup DBs that hold 0
  external targets (resolved without a library). This guard pins the
  library-attached behaviour so it cannot regress.

  CASES (markers in the fixture; lines are read from it)
    E1 S := TEdit(FControls[i]).Text          read  -> Vcl.StdCtrls.TEdit.Text (receiver_type_text TEdit)
    E2 okS: TEdit(FControls[i]).Text := S     write inside a case arm (the YADF shape) -> the same
    E3 TCheckBox(FArr[i]).Checked := True     array-of-TControl element cast -> Vcl.StdCtrls.TCheckBox.Checked
    P1 rename --plan uC.TMine.Text -> proved, E1 / E2 / E3 are another symbol's (exit 0)

  Needs the platform library C:\Projects\.drag-lint\library-Win64.sqlite (READ
  only). Missing library = FATAL, never a skip.
  Usage: pwsh -File tests\callresolve\run_library_cast_receiver_bind.ps1 [-Exe <drag-lint.exe>] [-LibraryDb <db>]
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$LibraryDb = "C:\Projects\.drag-lint\library-Win64.sqlite",
  [string]$WorkDir   = "C:\TEMP\draglint_lib_cast_$PID"
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

W (Join-Path $WorkDir 'uC.pas') @'
unit uC;

interface

uses
  System.Classes, Vcl.Controls, Vcl.StdCtrls;

type
  TKind = (okS, okB);

  TMine = class
  public
    Text: string;
  end;

  THost = class
  public
    FControls: TList;
    FArr: array of TControl;
    procedure Run(K: TKind; i: Integer);
  end;

implementation

procedure THost.Run(K: TKind; i: Integer);
var
  S: string;
begin
  S := TEdit(FControls[i]).Text; // E1
  case K of
    okS: TEdit(FControls[i]).Text := S; // E2
    okB: TCheckBox(FArr[i]).Checked := True; // E3
  end;
end;

end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;

uses
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
function LineOfMarker([string]$Marker) {
  $ls = [IO.File]::ReadAllLines((Join-Path $WorkDir 'uC.pas'))
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match ('// ' + [regex]::Escape($Marker) + '$')) { return $i + 1 } }
  return -1
}
function Expect([string]$Label, [string]$Marker, [string]$AName, [string]$Ext, [string]$Rt) {
  $ln = LineOfMarker $Marker
  $r = Sql ("SELECT r.kind, r.external_target AS ext, r.receiver_type_text AS rt FROM refs r JOIN files f ON f.id = r.file_id " +
            "WHERE r.kind = 'member-access' AND r.name_text = '$AName' AND r.start_line = $ln AND f.path LIKE '%\uC.pas'")
  $ok = ($r.Count -eq 1) -and ($r[0].ext -eq $Ext) -and ($r[0].rt -eq $Rt)
  Check $Label $ok ("rows=$($r.Count) " + (($r | ForEach-Object { "[$($_.kind) ext=$($_.ext) rt=$($_.rt)]" }) -join ' '))
}

Expect 'E1  S := TEdit(FControls[i]).Text: Vcl.StdCtrls.TEdit.Text'              'E1' 'Text'    'Vcl.StdCtrls.TEdit.Text'        'TEdit'
Expect 'E2  case arm TEdit(FControls[i]).Text := S: Vcl.StdCtrls.TEdit.Text'     'E2' 'Text'    'Vcl.StdCtrls.TEdit.Text'        'TEdit'
Expect 'E3  TCheckBox(FArr[i]).Checked := True: Vcl.StdCtrls.TCheckBox.Checked'  'E3' 'Checked' 'Vcl.StdCtrls.TCheckBox.Checked' 'TCheckBox'

Push-Location $WorkDir
try { $o = ($null | & $Exe rename --kind symbol --name 'uC.TMine.Text' --to Caption2 --db $db --library-db $LibraryDb --plan 2>&1 | Out-String); $code = $LASTEXITCODE } finally { Pop-Location }
Check 'P1  rename --plan uC.TMine.Text: proved, no receiver-untyped refusal' (($code -eq 0) -and ($o -notmatch 'receiver-untyped') -and ($o -match 'undecided: 0')) ("exit=$code " + (($o -split "`r?`n" | Where-Object { $_ -match 'decided|refused|proved' }) -join ' | '))

# NEGATIVE CONTROL (the YADF mechanism): the same project INDEXED without a library, the proof run WITH one -> no
# external target in the DB, and the proof refuses receiver-untyped. Proves P1 can fail.
$db0 = Join-Path $WorkDir 'NoLib.sqlite'
& $Exe index --project (Join-Path $WorkDir 'App.dpr') --db $db0 --library-db none 2>&1 | Out-Null
Push-Location $WorkDir
try { $o0 = ($null | & $Exe rename --kind symbol --name 'uC.TMine.Text' --to Caption2 --db $db0 --library-db $LibraryDb --plan 2>&1 | Out-String); $code0 = $LASTEXITCODE } finally { Pop-Location }
Check 'N1  DB resolved without a library: rename --plan refuses receiver-untyped (negative control)' (($o0 -match 'receiver-untyped') -and ($o0 -match 'not proved')) (($o0 -split "`r?`n" | Where-Object { $_ -match 'undecided|not proved' }) -join ' | ')
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_lib_cast_$PID")) { if (Test-Path -LiteralPath $d23) { [IO.Directory]::Delete($d23, $true) } }
}
