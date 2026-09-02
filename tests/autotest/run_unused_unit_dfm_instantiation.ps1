<#
  run_unused_unit_dfm_instantiation.ps1 -- a class instantiated by the sibling
  .dfm counts as a use of the unit that declares it.

  THE BUG (INBOX-b6-dfm-instantiation-is-not-counted-as-a-use.md)
  --------------------------------------------------------------------------------
  Reported by DataCopy: ~23 of their 66 `unused-unit-in-uses` findings. The rule
  builds the set of names a file references from the .PAS file id:

      Refs := AStore.GetReferencesFromFile(Fid);   // Fid is the .pas

  The sibling .dfm is a separate file with its own id, and it emits ZERO refs of
  its own -- so a class that appears only in the designer contributes nothing and
  the unit declaring it is reported as a dead import. The rule's own message has
  been carrying the confession ("classes instantiated only by the sibling .dfm
  ... are invisible to this check") instead of the behaviour.

  It is LINT-SIDE, not extractor-side: the type name is already in the index, on
  the DFM's component symbol, in `signature`:

      kind=form       name=frmMain  signature=TfrmMain
      kind=component  name=Widget1  signature=TMyWidget

  so no DRAGLINT_EXTRACTOR_VERSION bump and no reindex.

  THE FIXTURE DETAIL THAT DECIDES WHETHER THIS TEST MEANS ANYTHING
  --------------------------------------------------------------------------------
  The form class must NOT declare the published field. The first attempt at this
  fixture wrote the ordinary IDE-generated shape:

      TfrmMain = class(TComponent)
      published
        Widget1: TMyWidget;      <-- a type reference IN THE .PAS
      end;

  and the defect did not reproduce at all, because that declaration is itself a
  reference to TMyWidget and keeps the import alive through the normal path. The
  DFM contributes nothing either way, so the fixture proved nothing. Only when
  the .pas names the type NOWHERE is the DFM the sole evidence -- which is the
  shape the rule gets wrong, and the shape asserted below.

  TWO ARMS, and the second is what stops this passing with the rule switched off:

  (1) uWidgets, used ONLY from the .dfm, must NOT be reported.
  (2) uDeadImport, genuinely unused in the same unit, MUST still be reported.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_unused_unit_dfm"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  [System.IO.File]::WriteAllText($Path, ($Body -replace "`r`n", "`n" -replace "`n", "`r`n"),
                                 [System.Text.Encoding]::ASCII)
}

Write-Host '== unused-unit-in-uses: DFM instantiation ==' -ForegroundColor Cyan
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
$prj = Join-Path $WorkDir 'prj'
New-Item -ItemType Directory -Force -Path $prj | Out-Null

Write-Ascii (Join-Path $prj 'uWidgets.pas') @'
unit uWidgets;

interface

uses
  System.Classes;

type
  TMyWidget = class(TComponent)
  public
    procedure Poke;
  end;

implementation

procedure TMyWidget.Poke;
begin
end;

end.
'@

Write-Ascii (Join-Path $prj 'uDeadImport.pas') @'
unit uDeadImport;

interface

type
  TNeverUsed = class
  public
    procedure Nothing;
  end;

implementation

procedure TNeverUsed.Nothing;
begin
end;

end.
'@

# No published field: see the header. The .pas names TMyWidget nowhere.
Write-Ascii (Join-Path $prj 'uMainForm.pas') @'
unit uMainForm;

interface

uses
  System.Classes, uWidgets, uDeadImport;

type
  TfrmMain = class(TComponent)
  end;

implementation

end.
'@

Write-Ascii (Join-Path $prj 'uMainForm.dfm') @'
object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'Main'
  object Widget1: TMyWidget
    Left = 8
    Top = 8
  end
end
'@

$db  = Join-Path $WorkDir 'p.sqlite'
$rep = Join-Path $WorkDir 'rep.txt'
& $Exe index $prj --db $db --quiet 2>&1 | Out-Null
& $Exe lint-all --db $db --output $rep 2>&1 | Out-Null
$out  = if (Test-Path $rep) { Get-Content $rep -Raw } else { '' }
$uuiu = @(($out -split "`n") | Where-Object { $_ -match 'unused-unit-in-uses' })

# Precondition. Without it, an empty report -- a crashed lint, a fixture that
# failed to index -- would satisfy arm 1 by silence and read as a pass.
Check 'control: the rule ran and reported something' ($uuiu.Count -gt 0) `
  "unused-unit-in-uses lines=$($uuiu.Count)"

# The precondition on the INDEX side: the fix reads the type name out of the DFM
# component symbol's `signature`. If the DFM stopped being indexed, or stopped
# carrying the signature, arm 1 would go green for the wrong reason.
$symJson = Join-Path $WorkDir 'dfmsyms.json'
& $Exe sql --db $db --format json --output $symJson `
  --query "SELECT s.kind, s.signature FROM symbols s JOIN files f ON f.id = s.file_id WHERE f.path LIKE '%.dfm'" 2>&1 | Out-Null
$sigs = @()
if (Test-Path $symJson) { $sigs = @((Get-Content $symJson -Raw | ConvertFrom-Json).rows | ForEach-Object { $_[1] }) }
Check 'control: the .dfm component symbol carries TMyWidget in `signature`' `
  ($sigs -contains 'TMyWidget') ("signatures=" + ($sigs -join ','))

Check 'a unit instantiated ONLY by the sibling .dfm is NOT reported' `
  (-not (($uuiu -join "`n") -match 'uWidgets')) `
  'TMyWidget appears only in uMainForm.dfm'

Check 'POSITIVE CONTROL: a genuinely dead import in the same unit IS reported' `
  ((($uuiu -join "`n") -match 'uDeadImport')) `
  'without this, switching the rule off would pass the assertion above'

Write-Host ''
if ($script:Failed) { Write-Host 'DFM-INSTANTIATION GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'DFM-INSTANTIATION GUARD: PASS' -ForegroundColor Green
exit 0
