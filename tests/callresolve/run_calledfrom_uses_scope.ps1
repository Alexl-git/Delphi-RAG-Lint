<#
  run_calledfrom_uses_scope.ps1 -- an UNVERIFIED (name-matched) caller must come
  from a unit that can actually REACH the target's unit through the uses graph.

  THE BUG (INBOX-datacopy-2026-08-06 section 7 -- constructor Called from:
  misattributed across types)
  ---------------------------------------------------------------------------
  `document --apply` wrote this onto uZeissRoutines.TZEISSTransfer.Create:

    Called from: DPPRoutines.TDPPTransfer.TransferFile (DPPRoutines.pas),
                 uConfigurationService.TConfigurationService.Create (...),
                 uFileUtils.ISRunOnStartup (uFileUtils.pas), ... (+10 more)

  None of them call it, and the disproof is structural, not textual:
  uZeissRoutines' implementation uses uFileUtils, so uFileUtils cannot use
  uZeissRoutines -- Delphi rejects the circular interface reference. What those
  routines have in common is that each calls SOME `.Create` (TStringList,
  TIniFile, TRegIniFile). Measured on that index: 28 call refs named 'Create'
  and ZERO call_edges rows for any of them, so every one landed in the
  unverified name-match bucket of EVERY constructor in the index.

  THE RULE: a call from unit U to a symbol in unit T requires T to be reachable
  from U through uses (directly, or transitively when the member is inherited).
  The unverified bucket is now scoped to that reachable set. It is a filter on
  the '?' bucket only -- resolved call_edges callers are untouched.

  Fixture (four units, one DB):
    ctorunit  TZeiss.Create / TZeiss.Ping                -- the two targets
    nearunit  uses ctorunit; Build calls TZeiss.Create   -- REACHABLE, real
              Poke calls AHost.Ping(1) on a TObject      -- REACHABLE, unverified
    farunit   does NOT use ctorunit
              RunOnStartup calls TRegIniFile.Create(..)  -- UNREACHABLE noise
              Fake calls AHost.Ping(2)                   -- UNREACHABLE noise

  Both directions are asserted: the noise must be gone AND the reachable
  unverified caller must survive -- a "fix" that simply deleted the unverified
  bucket would pass the first half and fail the second.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-calledfrom-uses"
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

function Write-Unit($name, $text) {
  $t = $text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText((Join-Path $WorkDir "$name.pas"), $t, [System.Text.Encoding]::ASCII)
}

Write-Unit 'ctorunit' @'
unit ctorunit;

interface

type
  TZeiss = class
  public
    constructor Create(const AText: string);
    procedure Ping(const AValue: Integer);
  end;

implementation

constructor TZeiss.Create(const AText: string);
begin
  inherited Create;
end;

procedure TZeiss.Ping(const AValue: Integer);
begin
end;

end.
'@

Write-Unit 'nearunit' @'
unit nearunit;

interface

procedure Build;
procedure Poke(const AHost: TObject);

implementation

uses
  ctorunit;

procedure Build;
var
  Z: TZeiss;
begin
  Z:= TZeiss.Create('a');
  Z.Free;
end;

procedure Poke(const AHost: TObject);
begin
  { untypable receiver -> no call_edge, but this unit DOES use ctorunit }
  AHost.Ping(1);
end;

end.
'@

Write-Unit 'farunit' @'
unit farunit;

interface

procedure RunOnStartup;
procedure Fake(const AHost: TObject);

implementation

procedure RunOnStartup;
var
  Reg: TRegIniFile;
begin
  { some OTHER type's constructor -- must never be attributed to TZeiss.Create }
  Reg:= TRegIniFile.Create('Software\X');
  Reg.Free;
end;

procedure Fake(const AHost: TObject);
begin
  AHost.Ping(2);
end;

end.
'@

$db = Join-Path $WorkDir 'uses.sqlite'
& $Exe index $WorkDir --db $db --quiet 2>&1 | Out-Null

# ONE --unit pass, not two --qname passes: a second --qname apply anchors on the
# DB's now-stale StartLine (the first apply pushed every later decl down) and
# nests its block inside the first one.
& $Exe document --unit (Join-Path $WorkDir 'ctorunit.pas') --db $db --apply --no-backup 2>&1 | Out-Null
$txt = [IO.File]::ReadAllText((Join-Path $WorkDir 'ctorunit.pas'))

$lines  = $txt -split "`r?`n"
$idxCls = ($lines | Select-String -SimpleMatch 'TZeiss = class'     | Select-Object -First 1).LineNumber
$idxCr  = ($lines | Select-String -SimpleMatch 'constructor Create' | Select-Object -First 1).LineNumber
$idxPg  = ($lines | Select-String -SimpleMatch 'procedure Ping'     | Select-Object -First 1).LineNumber
# The managed block sits immediately ABOVE its declaration, so attribute each
# 'Called from:' line to the nearest declaration BELOW it.
$crLine = ($lines[0..($idxCr - 1)] | Where-Object { $_ -match 'Called from:' } | Select-Object -Last 1)
$pgLine = ($lines[$idxCr..($idxPg - 1)] | Where-Object { $_ -match 'Called from:' } | Select-Object -Last 1)

Write-Host 'TZeiss.Create -- constructor' -ForegroundColor Cyan
Check 'has a Called from: line' ($null -ne $crLine -and $crLine -ne '') "line=$crLine"
Check 'EXCLUDES farunit.RunOnStartup (farunit cannot use ctorunit)' `
  (-not ($crLine -match 'farunit')) 'the section-7 bug'
Check 'INCLUDES nearunit.Build (a real caller)' ($crLine -match 'nearunit\.Build')

Write-Host ''
Write-Host 'TZeiss.Ping -- unverified bucket still works when reachable' -ForegroundColor Cyan
Check 'INCLUDES nearunit.Poke (untypable receiver, but nearunit uses ctorunit)' `
  ($pgLine -match 'nearunit\.Poke') 'else the fix just deleted the unverified bucket'
Check 'EXCLUDES farunit.Fake (farunit cannot use ctorunit)' `
  (-not ($pgLine -match 'farunit'))

Write-Host ''
Write-Host 'TZeiss (the type) -- non-routine kinds take the same scope' -ForegroundColor Cyan
# For a NON-ROUTINE symbol this same bucket renders as 'Used by', and it runs
# KIND-BLIND (ACallSitesOnly=False), so it is the path where a non-call ref
# could reach the list. It must be scoped identically -- farunit does not use
# ctorunit, so nothing of farunit's belongs in the type's Used by either.
$clsBlock = ($lines[0..($idxCls - 1)] -join "`n")
Check 'INCLUDES nearunit (the unit that uses ctorunit)' ($clsBlock -match 'nearunit')
Check 'EXCLUDES farunit'                                (-not ($clsBlock -match 'farunit'))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
