<#
  run_dotted_lhs_uses_scope_guard.ps1 -- the LHS of a MEMBER ACCESS must be
  resolved with the hovering file's own uses clause, exactly as a bare
  identifier already is.

  THE DEFECT THIS PINS (owner, live IDE, 2026-08-19):

    C:\Projects\DataCopy\uMainZeissCopy.pas:4124
      Fnm := TPath.GetDirectoryName(Fnm);

      hovering TPath            -> System.IOUtils.TPath   (correct)
      hovering GetDirectoryName -> FMX.Objects.TPath      (WRONG)

  Two hovers on ONE expression disagreeing about what TPath is, is the tell.
  The bare-identifier branch of TTypeAtResolver.Resolve was given
  FindTypeAnywherePreferringUses on 2026-08-19; the DOTTED branch was not, and
  still resolves a direct-type LHS with FindTypeAnywhere -- unscoped, flat,
  first-hit. So the LHS lands on the wrong same-named type, the member is of
  course not found on it, and the owner-type floor reports that wrong type with
  full confidence.

  THE CONTROLS -- and why each one is load-bearing:

    * CONTROL A is the whole reason this guard is not a one-line change.
      UsedUnits does NOT contain the file's OWN unit. Preferring "declared under
      a used unit" therefore RANKS EVERY OTHER USED UNIT ABOVE THE FILE'S OWN
      DECLARATIONS -- the exact opposite of Delphi scoping, and field names
      (FList, FConnection) collide across units constantly. A naive fix passes
      the defect check and breaks this one.

    * CONTROL B: the filter must NARROW, never blank. A type that exists only
      in an unused unit is uncontested and must still resolve.

    * CONTROL C: hovering the LHS token itself must keep answering correctly.
      That path was fixed separately; if it regresses, the two hovers disagree
      again in the other direction.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-dotted-uses-scope"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$libDir = Join-Path $WorkDir 'lib'; New-Item -ItemType Directory $libDir | Out-Null
$appDir = Join-Path $WorkDir 'app'; New-Item -ItemType Directory $appDir | Out-Null

# --- the DECOY unit: sorts first, indexes first, NEVER used by the probe -----
WriteAnsi (Join-Path $libDir 'aaaDecoyGui.pas') @'
unit aaaDecoyGui;

interface

type
  TPathX = class
  public
    procedure DrawShape;
  end;

  TSoloDecoyType = class
  public
    procedure SoloMemberX;
  end;

implementation

procedure TPathX.DrawShape;
begin
end;

procedure TSoloDecoyType.SoloMemberX;
begin
end;

end.
'@

# --- the CORRECT owner: same type NAME, in a unit the probe DOES use ---------
WriteAnsi (Join-Path $libDir 'zzzIoLike.pas') @'
unit zzzIoLike;

interface

type
  TPathX = record
  public
    class function GetDirectoryNameX(const APath: string): string; static;
  end;

  TDecoyHolder = class
  public
    FSharedFieldX: Integer;
  end;

implementation

class function TPathX.GetDirectoryNameX(const APath: string): string;
begin
  Result := APath;
end;

end.
'@

# --- the probe: uses zzzIoLike ONLY, and declares its OWN FSharedFieldX ------
WriteAnsi (Join-Path $appDir 'uProbeDotted.pas') @'
unit uProbeDotted;

interface

uses
  zzzIoLike;

type
  TRealThing = class
  public
    procedure DoRealWorkX;
  end;

  TOwnerX = class
  public
    FSharedFieldX: TRealThing;
    procedure Run;
  end;

implementation

procedure TRealThing.DoRealWorkX;
begin
end;

procedure TOwnerX.Run;
var
  Fnm: string;
begin
  Fnm := TPathX.GetDirectoryNameX(Fnm);
  FSharedFieldX.DoRealWorkX;
end;

end.
'@

# --- CONTROL B probe: a type that exists ONLY in the unused decoy unit -------
WriteAnsi (Join-Path $appDir 'uSoloDotted.pas') @'
unit uSoloDotted;

interface

uses
  zzzIoLike;

procedure Go;

implementation

procedure Go;
begin
  TSoloDecoyType.SoloMemberX;
end;

end.
'@

$libDb = Join-Path $WorkDir 'lib.sqlite'
$appDb = Join-Path $WorkDir 'app.sqlite'
& $Exe index $libDir --db $libDb 2>&1 | Out-Null
& $Exe index $appDir --db $appDb 2>&1 | Out-Null
Check 'both indexes built' ((Test-Path $libDb) -and (Test-Path $appDb))

function ResolvedAt([string]$file, [string]$needle, [string]$token) {
  $ls = [System.IO.File]::ReadAllLines($file)
  $ln = -1
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i].Contains($needle)) { $ln = $i + 1; break } }
  if ($ln -lt 1) { return "<needle not found: $needle>" }
  $col = $ls[$ln - 1].IndexOf($token) + 4
  $out = & $Exe typeat "${file}:${ln}:${col}" --db $appDb --db $libDb 2>$null | Out-String
  $r = ''
  foreach ($l in ($out -split "`r?`n")) { if ($l -match '^\s*Resolved:\s*(.+?)\s*$') { $r = $matches[1] } }
  return $r
}

$probe = Join-Path $appDir 'uProbeDotted.pas'
$solo  = Join-Path $appDir 'uSoloDotted.pas'

# ---- THE DEFECT ------------------------------------------------------------
Write-Host ''
Write-Host 'THE DEFECT: a dotted MEMBER must use the file own uses to pick its LHS' -ForegroundColor Cyan
$got = ResolvedAt $probe 'TPathX.GetDirectoryNameX(Fnm)' 'GetDirectoryNameX'
Check 'member resolves on the USED unit type' ($got -eq 'zzzIoLike.TPathX.GetDirectoryNameX') "resolved='$got'"
Check 'it is NOT the decoy the file never uses'  ($got -notmatch 'aaaDecoyGui')                "resolved='$got'"

# ---- CONTROLS --------------------------------------------------------------
Write-Host ''
Write-Host 'CONTROLS' -ForegroundColor Cyan

# A. the file's OWN unit is not in its uses clause -- it must still win.
$gotA = ResolvedAt $probe 'FSharedFieldX.DoRealWorkX' 'DoRealWorkX'
Check 'CONTROL A: the file OWN field beats a same-named field in a USED unit' `
  ($gotA -eq 'uProbeDotted.TRealThing.DoRealWorkX') "resolved='$gotA'"

# B. narrow, never blank.
$gotB = ResolvedAt $solo 'TSoloDecoyType.SoloMemberX' 'SoloMemberX'
Check 'CONTROL B: an UNCONTESTED member from an unused unit still resolves' `
  ($gotB -match 'SoloMemberX') "resolved='$gotB'"

# C. hovering the LHS token itself must agree with the member hover.
$gotC = ResolvedAt $probe 'TPathX.GetDirectoryNameX(Fnm)' 'TPathX'
Check 'CONTROL C: hovering the LHS type names the SAME unit as the member' `
  ($gotC -match 'zzzIoLike') "resolved='$gotC'"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
