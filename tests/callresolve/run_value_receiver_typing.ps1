<#
  run_value_receiver_typing.ps1 -- a call receiver that is a VALUE in scope is
  typed: a unit-level var, an inherited field, and a chain that starts at one.

  THE PROBLEM (evaluation on ProjectA, 2026-09-28). TypeReceiver typed a bare
  receiver from a local or parameter, then from a member of the enclosing class
  declared ON THAT CLASS, then as a type name. It never looked at:
    * a UNIT-LEVEL var -- `FMain.Refresh`, `DM.Commit` -- which is how Delphi
      code reaches its forms and data modules, and the main cause of callers the
      evaluation found missing;
    * a field the class INHERITS (a base form's field);
    * a chain whose head is a value -- `DM.Qry.Open`, `Self.FList.Open` -- which
      the dotted rung read as a unit/type-qualified TYPE and found none.
  The `with` path already typed bare names correctly (TypeOfOrdinaryName).

  THE FIX (resolver 1.13.0-alpha). The receiver rungs use TypeOfValueName --
  local/parameter, class-chain member, exactly one visible unit var -- and a
  dotted chain whose head is a value walks TypeOfMember segment by segment.

  CONTROLS:
    * a LOCAL named like the global shadows it (Delphi's own rule);
    * two visible unit vars of one name decline (no guess).

  Usage: pwsh -File tests/callresolve/run_value_receiver_typing.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_value_receiver_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe"; exit 2 }
$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

Write-Ascii (Join-Path $src 'uData.pas') @'
unit uData;

interface

type
  TQuery = class(TObject)
  public
    procedure Open;
  end;

  TDataMod = class(TObject)
  public
    Qry: TQuery;
    procedure Commit;
  end;

  TOther = class(TObject)
  public
    procedure Ping;
  end;

var
  DM: TDataMod;

implementation

procedure TQuery.Open;
begin
end;

procedure TDataMod.Commit;
begin
end;

procedure TOther.Ping;
begin
end;

end.
'@
Write-Ascii (Join-Path $src 'uBase.pas') @'
unit uBase;

interface

uses
  uData;

type
  TBaseForm = class(TObject)
  protected
    FList: TQuery;
  end;

implementation

end.
'@
Write-Ascii (Join-Path $src 'uForm.pas') @'
unit uForm;

interface

uses
  uData, uBase;

type
  TMyForm = class(TBaseForm)
  public
    procedure GoGlobal;
    procedure GoChain;
    procedure GoInherited;
    procedure GoSelfChain;
    procedure GoShadow;
  end;

implementation

procedure TMyForm.GoGlobal;
begin
  DM.Commit;
end;

procedure TMyForm.GoChain;
begin
  DM.Qry.Open;
end;

procedure TMyForm.GoInherited;
begin
  FList.Open;
end;

procedure TMyForm.GoSelfChain;
begin
  Self.FList.Open;
end;

procedure TMyForm.GoShadow;
var
  DM: TOther;
begin
  DM.Ping;
end;

end.
'@
# Two units that each export a var named Twin, both used: an ambiguity.
foreach ($u in @('uTwinA', 'uTwinB')) {
  Write-Ascii (Join-Path $src "$u.pas") @"
unit $u;

interface

uses
  uData;

var
  Twin: TDataMod;

implementation

end.
"@
}
Write-Ascii (Join-Path $src 'uTwinUser.pas') @'
unit uTwinUser;

interface

procedure UseTwin;

implementation

uses
  uTwinA, uTwinB;

procedure UseTwin;
begin
  Twin.Commit;
end;

end.
'@

$db = Join-Path $WorkDir 'val.sqlite'
& $exePath index $src --db $db --quiet 2>&1 | Out-Null
Check 'precondition: index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

function Callees([string]$QName) { return ((& $exePath find-callees --qname $QName --db $db 2>$null) -join "`n") }

$g = Callees 'uForm.TMyForm.GoGlobal'
Check 'ASSERT: a unit-level var receiver types (DM.Commit)' ($g -match 'uData\.TDataMod\.Commit\s+\[certain\]') "callees: $g"
$c = Callees 'uForm.TMyForm.GoChain'
Check 'ASSERT: a chain from a unit var types member by member (DM.Qry.Open)' ($c -match 'uData\.TQuery\.Open\s+\[certain\]') "callees: $c"
$i = Callees 'uForm.TMyForm.GoInherited'
Check 'ASSERT: an INHERITED field receiver types (FList.Open)' ($i -match 'uData\.TQuery\.Open\s+\[certain\]') "callees: $i"
$s = Callees 'uForm.TMyForm.GoSelfChain'
Check 'ASSERT: a Self chain types (Self.FList.Open)' ($s -match 'uData\.TQuery\.Open\s+\[certain\]') "callees: $s"
$h = Callees 'uForm.TMyForm.GoShadow'
Check 'CONTROL: a LOCAL shadows the global of the same name (DM: TOther)' `
  (($h -match 'uData\.TOther\.Ping') -and ($h -notmatch 'TDataMod')) "callees: $h"
$t = Callees 'uTwinUser.UseTwin'
Check 'CONTROL: two visible unit vars of one name decline' ($t -notmatch 'TDataMod\.Commit') "callees: $t"

Write-Host ''
if ($script:fail) { Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'RESULT: PASS'; exit 0
} finally {
  foreach ($d in @("$env:TEMP\draglint_value_receiver_$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
