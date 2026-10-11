<#
  run_doc_callers_foreign_receiver.ps1 -- the "Called from:" fact must not claim
  an unresolved call whose receiver has a KNOWN declared type that is neither
  the target method's class nor a descendant of it.

  THE BUG (C14, filed 2026-09-30 by the converter stream)
  ------------------------------------------------------
  `FUnitList.ClearSelection` (FUnitList: TListView, a VCL type) has no
  call_edges row -- the resolver correctly leaves it unbound, because TListView
  is not in the project index. The doc-facts builder's unverified NAME bucket
  (FindUnresolvedNameCallers) then attributed it to the project's only
  `ClearSelection`, TWorkingSet.ClearSelection, and `doc-drift --fix` /
  `document --apply` wrote that edge into another unit's managed block:
    Called from: ..., ConvRules.MainForm.TConvRulesForm.UnitPopupPopup (...) ?
  The store's receiver filter keeps any receiver that names a value symbol,
  because a value's NAME says nothing about its type; but the value's DECLARED
  type is in the index and does.

  Cases (document --qname WorkingSet.TWorkingSet.ClearSelection, dry run)
    UnitPopup      field  FUnitList: TListView   MUST NOT be listed (library type)
    LocalPopup     local  LView: TListView       MUST NOT be listed
    DoClear        field  FSet: TWorkingSet      listed (positive control, resolved)
  (document --qname WorkingSet.TWorkingSet.ResetAll)
    ParamPopup     param  AList: TListView       MUST NOT be listed
    OtherPopup     field  FOther: TOtherThing    MUST NOT be listed (project class, unrelated)
    DoClearSpecial field  FSpecial: TSpecialSet  listed (positive control, descendant)
    TBox<T>.Run    field  FItem: T               listed with '?' (type unknown: kept)
  Plus: each skipped edge is reported on stderr, and doc-drift agrees with the
  block the writer produced (no drift right after --apply + reindex).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc-callers-foreign-$PID"
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
try {
  $srcDir = Join-Path $WorkDir 'src'
  New-Item -ItemType Directory $srcDir | Out-Null
  $db = Join-Path $WorkDir 'foreign.sqlite'
  $ws = @'
unit WorkingSet;

interface

type
  /// <summary>A working set.</summary>
  TWorkingSet = class
  public
    /// <summary>Clears the selection.</summary>
    procedure ClearSelection;
    /// <summary>Resets everything.</summary>
    procedure ResetAll;
  end;

  /// <summary>Something else, in the project.</summary>
  TOtherThing = class
  end;

implementation

procedure TWorkingSet.ClearSelection;
begin
end;

procedure TWorkingSet.ResetAll;
begin
end;

end.
'@
  $mf = @'
unit MainForm;

interface

uses
  Vcl.ComCtrls, WorkingSet;

type
  TSpecialSet = class(TWorkingSet)
  end;

  TBox<T> = class
  private
    FItem: T;
  public
    procedure Run;
  end;

  TMainForm = class
  private
    FUnitList: TListView;
    FSet: TWorkingSet;
    FSpecial: TSpecialSet;
    FOther: TOtherThing;
  public
    procedure UnitPopup;
    procedure LocalPopup;
    procedure ParamPopup(AList: TListView);
    procedure OtherPopup;
    procedure DoClear;
    procedure DoClearSpecial;
  end;

implementation

procedure TBox<T>.Run;
begin
  FItem.ClearSelection;
end;

procedure TMainForm.UnitPopup;
begin
  FUnitList.ClearSelection;
end;

procedure TMainForm.LocalPopup;
var
  LView: TListView;
begin
  LView := FUnitList;
  LView.ClearSelection;
end;

procedure TMainForm.ParamPopup(AList: TListView);
begin
  AList.ResetAll;
end;

procedure TMainForm.OtherPopup;
begin
  FOther.ResetAll;
end;

procedure TMainForm.DoClear;
begin
  FSet.ClearSelection;
end;

procedure TMainForm.DoClearSpecial;
begin
  FSpecial.ResetAll;
end;

end.
'@
  foreach ($p in @(@('WorkingSet.pas', $ws), @('MainForm.pas', $mf))) {
    $norm = $p[1] -replace "`r`n", "`n" -replace "`n", "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $srcDir $p[0]), $norm, [System.Text.Encoding]::ASCII)
  }

  & $Exe index $srcDir --db $db 2>&1 | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  # Two targets so that, even before the fix, neither list reaches the display
  # cap (docs.max_callers, default 5) -- a "(+N more)" tail would hide an entry
  # and make its not-listed check vacuous.
  function Get-Called([string]$QName) {
    $errFile = Join-Path $WorkDir 'doc.err'
    $out = (& $Exe document --qname $QName --db $db 2>$errFile) -join "`n"
    $err = if (Test-Path $errFile) { [System.IO.File]::ReadAllText($errFile) } else { '' }
    $called = ([regex]::Match($out, 'Called from:[^<]*')).Value
    Write-Host ("  {0}: {1}" -f $QName, $called) -ForegroundColor DarkGray
    return @{ Called = $called; Err = $err }
  }
  $qn = 'WorkingSet.TWorkingSet.ClearSelection'
  $c1 = Get-Called $qn
  $c2 = Get-Called 'WorkingSet.TWorkingSet.ResetAll'
  Check 'no list is capped (shape check)' (-not ($c1.Called -match '\(\+') -and -not ($c2.Called -match '\(\+'))

  Write-Host ''
  Write-Host 'Positive controls (a real or undecidable caller is still written)' -ForegroundColor Cyan
  Check 'DoClear (FSet: TWorkingSet, resolved) listed' ($c1.Called -match 'TMainForm\.DoClear \(')
  Check 'DoClearSpecial (FSpecial: TSpecialSet, descendant) listed' ($c2.Called -match 'TMainForm\.DoClearSpecial \(')
  Check 'TBox<T>.Run (FItem: T, type unknown) listed' ($c1.Called -match 'TBox(<T>)?\.Run \(')

  Write-Host ''
  Write-Host 'A receiver of a known, unrelated type is not a caller' -ForegroundColor Cyan
  Check 'UnitPopup (field: TListView) not listed' (-not ($c1.Called -match 'UnitPopup'))
  Check 'LocalPopup (local: TListView) not listed' (-not ($c1.Called -match 'LocalPopup'))
  Check 'ParamPopup (param: TListView) not listed' (-not ($c2.Called -match 'ParamPopup'))
  Check 'OtherPopup (field: TOtherThing) not listed' (-not ($c2.Called -match 'OtherPopup'))
  Check 'skipped edge reported on stderr, naming caller and type' (
    ($c1.Err -match 'UnitPopup') -and ($c1.Err -match 'TListView') -and ($c1.Err -match 'skipped'))
  Check 'skipped project-class edge reported on stderr' (
    ($c2.Err -match 'OtherPopup') -and ($c2.Err -match 'TOtherThing'))
  Write-Host ''
  Write-Host 'Checker agrees with the writer' -ForegroundColor Cyan
  & $Exe document --qname $qn --db $db --apply --no-backup 2>$null | Out-Null
  & $Exe index $srcDir --db $db 2>&1 | Out-Null
  $drift = @(& $Exe doc-drift --qname $qn --db $db --json 2>$null | Where-Object { "$_".Trim().StartsWith('{') })
  Check 'doc-drift clean after document --apply' ($drift.Count -eq 0) ($drift -join ' | ')
}
finally {
  if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
