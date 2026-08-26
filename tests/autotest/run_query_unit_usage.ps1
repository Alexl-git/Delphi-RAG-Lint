# Guard: `query unit-usage --in <file> --unit <U>` -- of U's EXPORTS, which does
# this file reference?
#
# The verb shipped in 571d006 and did not work on the case it was built for. Two
# structural defects, both measured against System.IniFiles in the Win32 library
# index before this guard was written:
#
#   1. It derived the export set with FindSymbolsByQualifiedName(<unit>). A
#      unit's members are qualified `System.IniFiles.TIniFile`, so an exact
#      qualified-name lookup on the UNIT name returns exactly ONE row -- the unit
#      symbol itself. The verb then answered about a one-element "export
#      surface". Members hang off the unit symbol as CHILDREN.
#   2. It resolved the unit in the SAME store as the target file. Those are
#      routinely different: a project index is the compile closure and excludes
#      library-path units, so "does this project file use System.IniFiles" needs
#      the project DB for the file and the LIBRARY DB for the unit. Resolving
#      both in one store produced "ERROR: no interface-section symbols found in
#      unit: System.IniFiles" -- on exactly the question it exists to answer.
#
# THE THREE ARMS, and each one fails differently if the verb regresses:
#
#   LIVE   -- uUser references TThing and DoIt. If this goes red the verb has
#             stopped finding real references, and the two "dead" arms below
#             would then pass for the wrong reason. This is the arm that stops
#             "reports nothing" from looking like success -- which is precisely
#             the state unused-unit-in-uses was found in.
#   DEAD   -- uDead uses uLib and references none of its exports.
#   PROSE  -- uProse names TThing ONLY in a `//` comment and in a string literal.
#             It must still be DEAD. This is the entire difference from grep, and
#             it is not hypothetical: the INBOX note that motivated this verb
#             claimed uZeissRoutines.pas used Vcl.Forms via
#             "Application.HandleException at line 2489", and every one of that
#             file's five `Application` mentions turned out to be inside a
#             comment saying the call had been REMOVED.
#
# Usage: pwsh -File tests/autotest/run_query_unit_usage.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-unit-usage"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory $work | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

Write-Ascii (Join-Path $work 'uLib.pas') @'
unit uLib;

interface

type
  TThing = class
  public
    procedure Poke;
  end;

procedure DoIt;

implementation

procedure TThing.Poke;
begin
end;

procedure DoIt;
begin
end;

end.
'@

Write-Ascii (Join-Path $work 'uUser.pas') @'
unit uUser;

interface

uses
  uLib;

procedure Go;

implementation

procedure Go;
var
  T: TThing;
begin
  T := TThing.Create;
  T.Poke;
  T.Free;
  DoIt;
end;

end.
'@

Write-Ascii (Join-Path $work 'uDead.pas') @'
unit uDead;

interface

uses
  uLib;

procedure Idle;

implementation

procedure Idle;
var
  N: Integer;
begin
  N := 1;
  Inc(N);
end;

end.
'@

Write-Ascii (Join-Path $work 'uProse.pas') @'
unit uProse;

interface

uses
  uLib;

procedure Talk;

implementation

procedure Talk;
var
  S: string;
begin
  // TThing used to be created here, and DoIt was called after it.
  S := 'TThing and DoIt appear only in this string literal';
  Writeln(S);
end;

end.
'@

$db = Join-Path $WorkDir 'uu.sqlite'
$idx = & $Exe index $work --db $db 2>&1
Check 'index exits 0' ($LASTEXITCODE -eq 0) "$($idx | Select-Object -Last 1)"

function UsageCount([string]$File) {
  $raw = (& $Exe query unit-usage --in (Join-Path $work $File) --unit 'uLib' --db $db) -join "`n"
  if ($raw -match '(\d+)\s+of\s+(\d+)\s+export') {
    return [pscustomobject]@{ Used = [int]$Matches[1]; Total = [int]$Matches[2]; Raw = $raw }
  }
  return [pscustomobject]@{ Used = -1; Total = -1; Raw = $raw }
}

Write-Host ''
Write-Host 'THE LIVE ARM -- without it, "0" everywhere would look like success' -ForegroundColor Cyan
$live = UsageCount 'uUser.pas'
Check 'uLib exports were discovered at all (total > 1)' ($live.Total -gt 1) "total=$($live.Total)"
Check 'uUser references at least one uLib export' ($live.Used -ge 1) "used=$($live.Used) of $($live.Total)"

Write-Host ''
Write-Host 'THE DEAD ARM' -ForegroundColor Cyan
$dead = UsageCount 'uDead.pas'
Check 'uDead references NONE of uLib''s exports' ($dead.Used -eq 0) "used=$($dead.Used) of $($dead.Total)"
Check 'and it saw the same export surface' ($dead.Total -eq $live.Total) "dead total=$($dead.Total) live total=$($live.Total)"

Write-Host ''
Write-Host 'THE PROSE ARM -- the whole difference from grep' -ForegroundColor Cyan
$prose = UsageCount 'uProse.pas'
Check 'a name in a COMMENT or STRING LITERAL is NOT a reference' ($prose.Used -eq 0) "used=$($prose.Used) of $($prose.Total); raw=$($prose.Raw)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
