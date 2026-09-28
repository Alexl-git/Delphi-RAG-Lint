<#
  run_object_leak_owner_arg_no_store.ps1 -- WITHOUT a store, a constructor
  called with the component-owner idiom (`TButton.Create(Self)`) is an
  ownership transfer, not a leak.

  WHY (INBOX-2026-09-24-converter-to-engine-list-units-and-object-leak #2): the
  converter's `drag-lint lint ConvRules.RuleChooser.pas` (no --db) reported
  `object-leak` on every `BtnX := TButton.Create(Self)`; with --db the same file
  was clean. ConstructorTransfersOwnership needs a store to prove the type is a
  TComponent, so on the store-free path it always said "no transfer".

  THE FIX, and its limit: store-free, a FIRST constructor argument of exactly
  Self / Application / Owner / AOwner is taken as the owner idiom. Nothing else
  is: Create(nil), Create(<some other variable>) and a no-argument Create stay
  leak-checked. With a store the precise TComponent check is unchanged.

  Every suppression has a "still fires" twin: an unowned TStringList, an explicit
  Create(nil), a Create(<other variable>) -- so a rule that stopped firing
  altogether fails here.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-leak-owner-arg-$PID"
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

$src = @(
  'unit uLeakOwner;'
  ''
  'interface'
  ''
  'uses'
  '  System.Classes, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Forms;'
  ''
  'type'
  '  TProbeForm = class(TForm)'
  '  private'
  '    Btm: TPanel;'
  '  public'
  '    procedure OwnedBySelfParentedToPanel;'
  '    procedure OwnedBySelfParentedToSelf;'
  '    procedure OwnedByApplication;'
  '    procedure OwnedByAOwner(AOwner: TComponent);'
  '    procedure ExplicitNilOwner;'
  '    procedure OwnedByOtherVariable(Holder: TComponent);'
  '    procedure Unowned;'
  '  end;'
  ''
  'implementation'
  ''
  'procedure TProbeForm.OwnedBySelfParentedToPanel;'
  'var'
  '  B1: TButton;'
  'begin'
  '  B1 := TButton.Create(Self);'
  '  B1.Parent := Btm;'
  'end;'
  ''
  'procedure TProbeForm.OwnedBySelfParentedToSelf;'
  'var'
  '  B2: TButton;'
  'begin'
  '  B2 := TButton.Create(Self);'
  '  B2.Parent := Self;'
  'end;'
  ''
  'procedure TProbeForm.OwnedByApplication;'
  'var'
  '  T3: TTimer;'
  'begin'
  '  T3 := TTimer.Create(Application);'
  'end;'
  ''
  'procedure TProbeForm.OwnedByAOwner(AOwner: TComponent);'
  'var'
  '  B4: TButton;'
  'begin'
  '  B4 := TButton.Create(AOwner);'
  'end;'
  ''
  'procedure TProbeForm.ExplicitNilOwner;'
  'var'
  '  B5: TButton;'
  'begin'
  '  B5 := TButton.Create(nil);'
  '  B5.Caption := ''x'';'
  'end;'
  ''
  'procedure TProbeForm.OwnedByOtherVariable(Holder: TComponent);'
  'var'
  '  B6: TButton;'
  'begin'
  '  B6 := TButton.Create(Holder);'
  '  B6.Caption := ''y'';'
  'end;'
  ''
  'procedure TProbeForm.Unowned;'
  'var'
  '  L7: TStringList;'
  'begin'
  '  L7 := TStringList.Create;'
  '  L7.Add(''z'');'
  'end;'
  ''
  'end.'
) -join "`r`n"
$pas = Join-Path $WorkDir 'uLeakOwner.pas'
[IO.File]::WriteAllText($pas, $src + "`r`n", [Text.Encoding]::ASCII)

$out = @(& $Exe lint $pas --rule object-leak 2>$null)
$flagged = @($out | Where-Object { $_ -match 'object-leak: Object "(\w+)"' } | ForEach-Object { [regex]::Match($_, 'Object "(\w+)"').Groups[1].Value.ToLower() } | Sort-Object -Unique)
Write-Host ("  flagged (store-free): [{0}]" -f ($flagged -join ', ')) -ForegroundColor DarkGray
Check 'the run is store-free (the lint says no index covers the file)' (@((& $Exe lint $pas --rule object-leak 2>&1) | Where-Object { "$_" -match 'no index covers this file' }).Count -ge 1)

Write-Host ''
Write-Host 'owner idiom -> ownership transfer, no finding' -ForegroundColor Cyan
Check 'TButton.Create(Self), parented to a PANEL (the converter shape) is NOT reported' (-not ($flagged -contains 'b1'))
Check 'TButton.Create(Self), parented to Self is NOT reported' (-not ($flagged -contains 'b2'))
Check 'TTimer.Create(Application) is NOT reported' (-not ($flagged -contains 't3'))
Check 'TButton.Create(AOwner) is NOT reported' (-not ($flagged -contains 'b4'))

Write-Host ''
Write-Host 'controls -> still reported' -ForegroundColor Cyan
Check 'TButton.Create(nil) IS reported (explicit nil owner: nobody frees it)' ($flagged -contains 'b5')
Check 'TButton.Create(<other variable>) IS still reported store-free (not the idiom)' ($flagged -contains 'b6')
Check 'an unowned TStringList.Create IS reported (the rule still works)' ($flagged -contains 'l7')

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
