<#
  run_named_arg_ownership.ps1 -- lane 152b GF1 row 1 (GRL regression, grammar v1.4.9 exprArgNamed).

  WHY: since grammar v1.4.9 an Automation NAMED argument `Foo(Name := Value)` parses as
  (exprArgs (exprArgNamed name: value:)). Two ownership readers took the WRAPPER for the
  argument and missed the object passed as the VALUE:
    object-leak             Flow.Lattices.CollectCallArgs  (LeftmostBaseVar on the wrapper)
    field-created-not-freed OwnershipChecks.MarkHandled     (NodeStr of the wrapper = "item := fitem")
  -> an object handed on by a named argument was reported as leaked, and the fixer proposed
  FreeAndNil(FItem) for a field the destructor had handed on ([risky], wrong).

  THE FIX: both readers judge the named argument's VALUE (ArgValueNode); the LABEL is never a
  read, so a label that happens to spell a local / field name hands nothing on.

  Positive controls (fail when the rule is off or the unwrap reads the label):
    * a field created and never handed on still fires field-created-not-freed + its FreeAndNil fix;
    * a field whose NAME is only a label (`V.Add(FLabel := 0)`) still fires;
    * a local created and never handed on still fires object-leak;
    * a local whose NAME is only a label (`Sheet.Take(L := 1)`) still fires object-leak;
    * the positional twins (V.Add(FPos) / Sheet.Take(P)) stay clean.
  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-named-arg-own-$PID"
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
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
[IO.Directory]::CreateDirectory($WorkDir) | Out-Null

$src = @(
  'unit uNamedArgOwn;'
  ''
  'interface'
  ''
  'type'
  '  TOwner = class'
  '  private'
  '    FItem: TObject;'
  '    FPos: TObject;'
  '    FNever: TObject;'
  '    FLabel: TObject;'
  '  public'
  '    constructor Create;'
  '    destructor Destroy; override;'
  '  end;'
  ''
  'procedure HandOnNamed(const Sheet: OleVariant);'
  'procedure HandOnPositional(const Sheet: OleVariant);'
  'procedure NeverHandedOn(const Sheet: OleVariant);'
  'procedure LabelOnly(const Sheet: OleVariant);'
  ''
  'implementation'
  ''
  'constructor TOwner.Create;'
  'begin'
  '  inherited Create;'
  '  FItem := TObject.Create;'
  '  FPos := TObject.Create;'
  '  FNever := TObject.Create;'
  '  FLabel := TObject.Create;'
  'end;'
  ''
  'destructor TOwner.Destroy;'
  'var'
  '  V: OleVariant;'
  'begin'
  '  V.Add(Item := FItem);'
  '  V.Add(FPos);'
  '  V.Add(FLabel := 0);'
  '  inherited Destroy;'
  'end;'
  ''
  'procedure HandOnNamed(const Sheet: OleVariant);'
  'var'
  '  O: TObject;'
  'begin'
  '  O := TObject.Create;'
  '  Sheet.Take(Obj := O);'
  'end;'
  ''
  'procedure HandOnPositional(const Sheet: OleVariant);'
  'var'
  '  P: TObject;'
  'begin'
  '  P := TObject.Create;'
  '  Sheet.Take(P);'
  'end;'
  ''
  'procedure NeverHandedOn(const Sheet: OleVariant);'
  'var'
  '  N: TObject;'
  'begin'
  '  N := TObject.Create;'
  '  Sheet.Take(0);'
  'end;'
  ''
  'procedure LabelOnly(const Sheet: OleVariant);'
  'var'
  '  L: TObject;'
  'begin'
  '  L := TObject.Create;'
  '  Sheet.Take(L := 1);'
  'end;'
  ''
  'end.'
) -join "`r`n"
$pas = Join-Path $WorkDir 'uNamedArgOwn.pas'
[IO.File]::WriteAllText($pas, $src + "`r`n", [Text.Encoding]::ASCII)

Push-Location $WorkDir
try {
  $raw = (& $Exe lint $pas --json 2>$null) -join "`n"
  $rows = @($raw | ConvertFrom-Json)
  Check 'lint --json answered (non-empty array)' ($rows.Count -gt 0) "rows=$($rows.Count)"
  $leak  = @($rows | Where-Object { $_.rule -eq 'object-leak' } | ForEach-Object { [regex]::Match($_.message, 'Object "(\w+)"').Groups[1].Value.ToLower() })
  $field = @($rows | Where-Object { $_.rule -eq 'field-created-not-freed' } | ForEach-Object { [regex]::Match($_.message, 'Field (\w+) ').Groups[1].Value.ToLower() })
  Write-Host ("  object-leak: [{0}]  field-created-not-freed: [{1}]" -f ($leak -join ', '), ($field -join ', ')) -ForegroundColor DarkGray

  Write-Host 'named argument VALUE hands the object on -> no finding' -ForegroundColor Cyan
  Check 'object-leak NOT reported for O (Sheet.Take(Obj := O))' (-not ($leak -contains 'o'))
  Check 'field-created-not-freed NOT reported for FItem (V.Add(Item := FItem))' (-not ($field -contains 'fitem'))

  Write-Host 'positional twins -> still clean' -ForegroundColor Cyan
  Check 'object-leak NOT reported for P (Sheet.Take(P))' (-not ($leak -contains 'p'))
  Check 'field-created-not-freed NOT reported for FPos (V.Add(FPos))' (-not ($field -contains 'fpos'))

  Write-Host 'positive controls -> still reported (rule on, label is not a read)' -ForegroundColor Cyan
  Check 'object-leak IS reported for N (never handed on)' ($leak -contains 'n')
  Check 'object-leak IS reported for L (L only spelled as a LABEL: Sheet.Take(L := 1))' ($leak -contains 'l')
  Check 'field-created-not-freed IS reported for FNever' ($field -contains 'fnever')
  Check 'field-created-not-freed IS reported for FLabel (V.Add(FLabel := 0))' ($field -contains 'flabel')

  Write-Host 'autofix (dry run) -> no FreeAndNil for a handed-on field' -ForegroundColor Cyan
  $fix = (& $Exe lint --in $pas --fix 2>$null) -join "`n"
  Check 'the fix plan answered' ($fix -match 'File:')
  Check 'NO FreeAndNil(FItem) proposed' (-not ($fix -match 'FreeAndNil\(FItem\)'))
  Check 'FreeAndNil(FNever) IS proposed (positive control)' ($fix -match 'FreeAndNil\(FNever\)')
} finally { Pop-Location }

[IO.Directory]::Delete($WorkDir, $true)
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
