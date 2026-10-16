<#
  run_purity_scoped_matches_full.ps1 -- a SCOPED purity pass writes exactly
  what a WHOLE pass writes (S4, 2026-10-08).

  Why this exists
  ---------------
  After a scoped call-target pass the purity stage re-derives only the routines
  whose verdict can have moved -- the routines of the rewritten files, the
  enclosing routines of every re-resolved ref, the methods of classes whose
  heritage reaches the change, and all of their transitive callers (plus the
  same-named methods of descendant classes, for a bare `inherited;`). Every other
  routine keeps its stored verdict. That is only correct if the closure misses
  nothing, and a miss is SILENT: a stale verdict looks like any other.

  So the test is differential. For each edit, the SAME baseline database is
  copied twice and the SAME edited tree is indexed into both: once as shipped
  (scoped), once with DRAGLINT_NO_SCOPED_PURITY=1 (whole). Every routine's
  effect_free / effect_summary / effect_witness must be identical.

  Edits (each from the unedited baseline):
    E1  a leaf routine gains a global write      -> its transitive callers move
    E2  a base method stops writing its field   -> the override that only calls
                                                   bare `inherited;` moves (no edge)
    E3  a called routine is deleted             -> its caller's ref unbinds
    E4  a new routine is added and called       -> new edge, new verdict
    E5  a field moves out of the base class     -> a descendant method's
                                                   classification changes (no call)
  CONTROL: each scoped run actually limited itself ("scoped to N routine(s)"
  with N below the total), else the comparison proves nothing.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_purity_scoped_$PID"
)
try {

$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

Write-Host '== scoped purity == whole purity ==' -ForegroundColor Cyan
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Force -Path $src | Out-Null

$units = [ordered]@{
  'uBase.pas' = @'
unit uBase;
interface
type
  TBase = class
  protected
    FCount: Integer;
  public
    procedure Bump; virtual;
  end;
implementation
procedure TBase.Bump;
begin
  FCount:= FCount + 1;
end;
end.
'@
  'uMid.pas' = @'
unit uMid;
interface
uses uBase;
type
  TMid = class(TBase)
  public
    procedure Bump; override;
    procedure Touch;
  end;
implementation
procedure TMid.Bump;
begin
  inherited;
end;
procedure TMid.Touch;
begin
  FCount:= 0;
end;
end.
'@
  'uUtil.pas' = @'
unit uUtil;
interface
var
  GTotal: Integer;
function Twice(AValue: Integer): Integer;
procedure SetTotal(AValue: Integer);
function UsesTwice(AValue: Integer): Integer;
procedure UsesSetTotal;
implementation
function Twice(AValue: Integer): Integer;
begin
  Result:= AValue * 2;
end;
procedure SetTotal(AValue: Integer);
begin
  GTotal:= AValue;
end;
function UsesTwice(AValue: Integer): Integer;
begin
  Result:= Twice(AValue) + 1;
end;
procedure UsesSetTotal;
begin
  SetTotal(3);
end;
end.
'@
  'uApp.pas' = @'
unit uApp;
interface
function Top(AValue: Integer): Integer;
procedure RunMid;
implementation
uses uUtil, uMid;
function Top(AValue: Integer): Integer;
begin
  Result:= UsesTwice(AValue);
end;
procedure RunMid;
var
  M: TMid;
begin
  M:= TMid.Create;
  try
    M.Bump;
  finally
    M.Free;
  end;
end;
end.
'@
  'uOther1.pas' = "unit uOther1;`ninterface`nfunction One: Integer;`nimplementation`nfunction One: Integer;`nbegin`n  Result:= 1;`nend;`nend.`n"
  'uOther2.pas' = "unit uOther2;`ninterface`nfunction Two: Integer;`nimplementation`nfunction Two: Integer;`nbegin`n  Result:= 2;`nend;`nend.`n"
}
foreach ($k in $units.Keys) { Write-Ascii (Join-Path $src $k) $units[$k] }
$base = Join-Path $WorkDir 'base.sqlite'

function Index([string]$db, [bool]$whole) {
  if ($whole) { $env:DRAGLINT_NO_SCOPED_PURITY = '1' } else { Remove-Item Env:DRAGLINT_NO_SCOPED_PURITY -ErrorAction SilentlyContinue }
  try {
    $o = @(& $Exe index $src --db $db 2>&1 | ForEach-Object { "$_" })
  } finally { Remove-Item Env:DRAGLINT_NO_SCOPED_PURITY -ErrorAction SilentlyContinue }
  return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($o -join "`n") }
}
function Verdicts([string]$db) {
  $q = "SELECT s.qualified_name || '@' || s.start_line || ' | ' || ifnull(f.effect_free,'NULL') || ' | ' || ifnull(f.effect_summary,'') || ' | ' || ifnull(f.effect_witness,'') AS v FROM symbol_facts f JOIN symbols s ON s.id = f.symbol_id WHERE ifnull(f.body_loc,0) > 0 ORDER BY 1"
  return ((& $Exe sql --db $db --format text --query $q 2>&1) | ForEach-Object { "$_" } | Where-Object { $_ -match ' \| ' }) -join "`n"
}

Push-Location C:\TEMP
try {
  $b = Index $base $true
  Check 'baseline indexed (whole)' ($b.Code -eq 0) $b.Text
  $baseVerdicts = Verdicts $base
  Check 'baseline has verdicts for the fixture routines' ($baseVerdicts -match 'uUtil\.UsesTwice') $baseVerdicts

  $edits = @(
    @{ Id = 'E1'; File = 'uUtil.pas'; Why = 'a leaf routine gains a global write';
       From = "  Result:= AValue * 2;"; To = "  GTotal:= AValue;`r`n  Result:= AValue * 2;"; Moves = 'uApp.Top' },
    @{ Id = 'E2'; File = 'uBase.pas'; Why = 'a base method stops writing its field';
       From = "  FCount:= FCount + 1;"; To = "  ;"; Moves = 'uMid.TMid.Bump' },
    @{ Id = 'E3'; File = 'uUtil.pas'; Why = 'a called routine is deleted';
       From = "procedure SetTotal(AValue: Integer);`r`nbegin`r`n  GTotal:= AValue;`r`nend;`r`n"; To = ''; Moves = 'uUtil.UsesSetTotal' },
    @{ Id = 'E4'; File = 'uOther1.pas'; Why = 'a new routine is added and called';
       From = "function One: Integer;`r`nbegin`r`n  Result:= 1;"; To = "var G1: Integer;`r`nprocedure Poke;`r`nbegin`r`n  G1:= 1;`r`nend;`r`nfunction One: Integer;`r`nbegin`r`n  Poke;`r`n  Result:= 1;"; Moves = 'uOther1.One' },
    @{ Id = 'E5'; File = 'uBase.pas'; Why = 'a field moves out of the base class';
       From = "  protected`r`n    FCount: Integer;`r`n"; To = "  protected`r`n"; Moves = 'uMid.TMid.Touch' }
  )
  foreach ($e in $edits) {
    Write-Host "$($e.Id) -- $($e.Why)" -ForegroundColor Cyan
    $path = Join-Path $src $e.File
    $orig = [System.IO.File]::ReadAllText($path)
    if (-not $orig.Contains($e.From)) { Check "$($e.Id) fixture edit applies" $false $e.From; continue }
    [System.IO.File]::WriteAllText($path, $orig.Replace($e.From, $e.To), [System.Text.Encoding]::ASCII)
    [System.IO.File]::SetLastWriteTimeUtc($path, (Get-Date).ToUniversalTime().AddSeconds(30))
    try {
      $dbS = Join-Path $WorkDir "$($e.Id)-scoped.sqlite"
      $dbW = Join-Path $WorkDir "$($e.Id)-whole.sqlite"
      Copy-Item $base $dbS
      Copy-Item $base $dbW
      $s = Index $dbS $false
      $w = Index $dbW $true
      Check "$($e.Id) both runs exit 0" (($s.Code -eq 0) -and ($w.Code -eq 0)) "$($s.Text)`n---`n$($w.Text)"
      $m = [regex]::Match($s.Text, 'resolve: purity -- (\d+) routine\(s\).*scoped to (\d+) routine\(s\)')
      Check "$($e.Id) CONTROL: the scoped run limited itself" ($m.Success -and ([int]$m.Groups[2].Value -lt [int]$m.Groups[1].Value)) `
        (($s.Text -split "`n") | Where-Object { $_ -match 'resolve: (purity|calls)' } | Out-String)
      Check "$($e.Id) the whole run did NOT limit itself" ($w.Text -notmatch 'scoped to \d+ routine') ''
      $vs = Verdicts $dbS
      $vw = Verdicts $dbW
      Check "$($e.Id) scoped verdicts == whole verdicts (every routine)" ($vs -eq $vw) `
        ((Compare-Object ($vs -split "`n") ($vw -split "`n") | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join "`n")
      $before = (($baseVerdicts -split "`n") | Where-Object { $_ -like "$($e.Moves)@*" }) -join ''
      $after  = (($vw -split "`n") | Where-Object { $_ -like "$($e.Moves)@*" }) -join ''
      Check "$($e.Id) CONTROL: the edit really moved $($e.Moves)" ($before -ne $after) "before: $before / after: $after"
    } finally {
      [System.IO.File]::WriteAllText($path, $orig, [System.Text.Encoding]::ASCII)
      [System.IO.File]::SetLastWriteTimeUtc($path, (Get-Date).ToUniversalTime().AddSeconds(60))
    }
  }
} finally { Pop-Location }

Write-Host ''
if ($script:Failed) { Write-Host 'PURITY SCOPED == WHOLE: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PURITY SCOPED == WHOLE: PASS' -ForegroundColor Green
exit 0
} finally {
  Remove-Item Env:DRAGLINT_NO_SCOPED_PURITY -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath "$env:TEMP\draglint_purity_scoped_$PID") { Remove-Item -LiteralPath "$env:TEMP\draglint_purity_scoped_$PID" -Recurse -Force -ErrorAction SilentlyContinue }
}
