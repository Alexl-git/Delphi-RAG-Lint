<#
  run_doc_drift_exception_fps.ps1 -- E17 (X-14 residue): three doc-drift
  ddExceptionNotRaised false findings on drag-lint's own tree, 2026-10-26.

    1 BARE RAISE   DRagLint.Storage.SQLite.ExecAdditiveDDL documents
                   <exception cref="EFDDBEngineException"> and its body is
                   `except on E: Exception do if not ... then raise;`. The bare
                   re-raise names no class, so the miner records nothing, and the
                   rule said "the body never raises it" about a routine whose
                   whole point is to let that exception escape.
    2 CALLEE RAISE DRagLint.Analysis.PurityStage.TPurityStage.Run documents
                   EInvalidOperation "propagated from PutEffectFacts". The raise
                   is reached through ISymbolStore.PutEffectFacts -- an INTERFACE
                   method, bodyless, so the transitive walk stopped there. The
                   interface method's own <exception cref> IS its contract (the
                   rule already refuses to grade it for that reason).
    3 AUTO BLOCK   TSQLiteSymbolStore.UpsertUnitUse carries an ENGINE-written
                   <exception cref="Exception"><!-- drag-lint:auto exc -->via ...
                   whose callee no longer raises. The finding is true, but it was
                   reported as not fixable although a regenerating --fix drops
                   exactly that tag (Regions: an AUTO_EXC tag is engine-owned and
                   only re-emitted while the body still raises the class).

  Asserts (doc-drift --qname X --json on an inline fixture):
    RED-1a ExecCatchAll    on E: Exception do raise;  cref EDbErr  -> no finding
    RED-1b ExecBareExcept  except raise; end;         cref EDbErr  -> no finding
    RED-1c ExecNarrowSame  on E: EBar do raise;       cref EBar    -> no finding
    RED-2  TStage.Run      FStore.Put (IStore.Put documents EInvalidOp) -> no finding
    RED-3  AutoStale       engine-written stale cref -> finding, fixable=true
    CONTROL-1 ExecNarrow   on E: EBar do raise;  cref EBaz -> STILL reported
    CONTROL-2 ExecSwallow  on E: Exception do ;  cref EDbErr -> STILL reported
    CONTROL-3 TStage.RunGet FStore.Get (no contract) -> STILL reported
    CONTROL-4 HandStale    hand-written stale cref -> reported, fixable=false
  BASELINE 2026-10-26 against the deployed 1.35.1-alpha exe: RED-* FAIL,
  CONTROL-* PASS.
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-docdrift-excfp-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory -Force $work | Out-Null
$body = @'
unit xfp;

interface

uses
  System.SysUtils;

type
  EDbErr = class(Exception);
  EBar = class(Exception);
  EBaz = class(Exception);
  EInvalidOp = class(Exception);

  IStore = interface
    ['{6A1D3C55-0B7E-4C61-9C1E-2F4B8E0A7D11}']
    /// <summary>Writes the rows.</summary>
    /// <exception cref="EInvalidOp">The store is read-only.</exception>
    procedure Put;
    /// <summary>Reads the rows.</summary>
    procedure Get;
  end;

  TStore = class(TInterfacedObject, IStore)
  public
    procedure Put;
    procedure Get;
  end;

  TStage = class
  private
    FStore: IStore;
  public
    /// <summary>Runs the stage.</summary>
    /// <exception cref="EInvalidOp">Propagated from Put.</exception>
    procedure Run;
    /// <summary>Runs the read half.</summary>
    /// <exception cref="EInvalidOp">Wrong: Get declares no such contract.</exception>
    procedure RunGet;
  end;

/// <summary>Does nothing.</summary>
procedure Helper;
/// <summary>Re-raises from a catch-all handler.</summary>
/// <exception cref="EDbErr">Re-raised for every other failure.</exception>
procedure ExecCatchAll;
/// <summary>Re-raises from a bare except block.</summary>
/// <exception cref="EDbErr">Re-raised.</exception>
procedure ExecBareExcept;
/// <summary>Re-raises EBar only.</summary>
/// <exception cref="EBar">Re-raised.</exception>
procedure ExecNarrowSame;
/// <summary>Re-raises EBar only.</summary>
/// <exception cref="EBaz">Wrong: only EBar is re-raised.</exception>
procedure ExecNarrow;
/// <summary>Swallows everything.</summary>
/// <exception cref="EDbErr">Wrong: swallowed.</exception>
procedure ExecSwallow;
/// <summary>Engine-written stale tag.</summary>
/// <exception cref="Exception"><!-- drag-lint:auto exc -->via xfp.Helper: gone</exception>
procedure AutoStale;
/// <summary>Hand-written stale tag.</summary>
/// <exception cref="Exception">Hand written and wrong.</exception>
procedure HandStale;

implementation

procedure TStore.Put;
begin
  raise EInvalidOp.Create('read-only');
end;

procedure TStore.Get;
begin
end;

procedure TStage.Run;
begin
  FStore.Put;
end;

procedure TStage.RunGet;
begin
  FStore.Get;
end;

procedure Helper;
begin
end;

procedure ExecCatchAll;
begin
  try
    Helper;
  except on E: Exception do
    if E.Message <> '' then raise;
  end;
end;

procedure ExecBareExcept;
begin
  try
    Helper;
  except
    raise;
  end;
end;

procedure ExecNarrowSame;
begin
  try
    Helper;
  except on E: EBar do
    raise;
  end;
end;

procedure ExecNarrow;
begin
  try
    Helper;
  except on E: EBar do
    raise;
  end;
end;

procedure ExecSwallow;
begin
  try
    Helper;
  except on E: Exception do
    ;
  end;
end;

procedure AutoStale;
begin
  Helper;
end;

procedure HandStale;
begin
  Helper;
end;

end.
'@
$norm = $body -replace "`r`n", "`n" -replace "`n", "`r`n"
[System.IO.File]::WriteAllText((Join-Path $work 'xfp.pas'), $norm, [System.Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'xfp.sqlite'
if (Test-Path $db) { [IO.File]::Delete($db) }
$null = & $Exe index $work --db $db --library-db none 2>&1
Check 'SANITY index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

function Get-Drift([string]$QName) {
  $rows = @()
  foreach ($ln in @(& $Exe doc-drift --qname $QName --db $db --json 2>$null)) {
    $t = "$ln".Trim()
    if ($t.StartsWith('{')) { $rows += ($t | ConvertFrom-Json) }
  }
  return ,$rows
}
function ExRows($rows) { return ,@($rows | Where-Object { $_.kind -eq 'ddExceptionNotRaised' }) }

$q = 'xfp.ExecSwallow'
$r = ExRows (Get-Drift $q)
Check 'SANITY/CONTROL-2 ExecSwallow (swallowing catch-all) still reports EDbErr' ($r.Count -eq 1 -and $r[0].detail -match 'EDbErr') "n=$($r.Count)"
$r = ExRows (Get-Drift 'xfp.ExecNarrow')
Check 'CONTROL-1 ExecNarrow (on EBar do raise; cref EBaz) still reported' ($r.Count -eq 1 -and $r[0].detail -match 'EBaz') "n=$($r.Count)"
$r = ExRows (Get-Drift 'xfp.TStage.RunGet')
Check 'CONTROL-3 TStage.RunGet (interface callee without contract) still reported' ($r.Count -eq 1) "n=$($r.Count)"
$r = ExRows (Get-Drift 'xfp.HandStale')
Check 'CONTROL-4 HandStale reported and NOT fixable' ($r.Count -eq 1 -and -not $r[0].fixable) "n=$($r.Count) fixable=$($r[0].fixable)"

$r = ExRows (Get-Drift 'xfp.ExecCatchAll')
Check 'RED-1a ExecCatchAll (catch-all re-raise) no finding' ($r.Count -eq 0) "n=$($r.Count)"
$r = ExRows (Get-Drift 'xfp.ExecBareExcept')
Check 'RED-1b ExecBareExcept (bare except re-raise) no finding' ($r.Count -eq 0) "n=$($r.Count)"
$r = ExRows (Get-Drift 'xfp.ExecNarrowSame')
Check 'RED-1c ExecNarrowSame (on EBar do raise; cref EBar) no finding' ($r.Count -eq 0) "n=$($r.Count)"
$r = ExRows (Get-Drift 'xfp.TStage.Run')
Check 'RED-2 TStage.Run (IStore.Put contract declares EInvalidOp) no finding' ($r.Count -eq 0) "n=$($r.Count)"
$r = ExRows (Get-Drift 'xfp.AutoStale')
Check 'RED-3 AutoStale reported AND fixable' ($r.Count -eq 1 -and $r[0].fixable) "n=$($r.Count) fixable=$($r[0].fixable)"

if ($script:Failed) { Write-Host "run_doc_drift_exception_fps: FAIL ($script:Passed passed)" -ForegroundColor Red; exit 1 }
Write-Host "run_doc_drift_exception_fps: PASS ($script:Passed checks)" -ForegroundColor Green
exit 0
} catch {
  Write-Host "FATAL: $_" -ForegroundColor Red
  exit 2
}
