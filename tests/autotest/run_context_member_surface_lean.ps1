<#
  run_context_member_surface_lean.ps1 --
  For a MEMBER target (method, field, property) the lean `## Class surface`
  lists the owner's declarations WITHOUT their comment-only lines; the
  target's own doc is already in `## Doc`.

  THE DEFECT (stats\draglint-gaps.log 2026-10-30, GAP-CONTEXT).
    context --task "modify TSQLiteSymbolStore.ResolveDispatch"
  was 47.5k tokens. Its class surface was 2457 lines, 2256 of them `///` doc
  comments of the OTHER members -- 92% of the surface, prose the reader of one
  method does not need (the surface's job is the owner's shape: signatures).

  THE RULE. Member target + lean mode (no --full-surface): lines whose first
  non-blank text is `//` are dropped from the class surface. A TYPE target keeps
  them (the members' docs are what a type-shaped task asks for), and
  --full-surface keeps them for every target.

  CONTROLS:
    * every member signature is still listed for the method target
    * the TYPE target keeps the member docs  -> the rule is scoped, not global
    * --full-surface keeps them              -> the switch still works
    * the target's own doc is still in ## Doc

  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_context_member_surface_lean_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Write-Ascii($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null

Write-Ascii (Join-Path $src 'uLean.pas') @"
unit uLean;

interface

type
  TWorker = class
  public
    /// <summary>OneDocProse for One.</summary>
    procedure One;
    /// <summary>TwoDocProse for Two.</summary>
    /// <param name="A">TwoParamProse.</param>
    function Two(A: Integer): Integer;
    // LooseNoteProse about Three.
    procedure Three;
  end;

implementation

procedure TWorker.One;
begin
end;

function TWorker.Two(A: Integer): Integer;
begin
  Result := A;
end;

procedure TWorker.Three;
begin
end;

end.
"@

$db = Join-Path $WorkDir 'fx.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

function Bundle([string]$Task, [switch]$Full) {
  $extra = @()
  if ($Full) { $extra = @('--full-surface') }
  return ((& $exePath context --task $Task --db $db --format markdown @extra 2>$null) -join "`n")
}
function Section([string]$Text, [string]$Head) {
  if ($Text -match ('(?s)## ' + $Head + '\n(.*?)(\n## |\z)')) { return $Matches[1] }
  return ''
}

$m    = Bundle 'modify uLean.TWorker.One'
$ms   = Section $m 'Class surface'
Check 'V the method target has a Class surface section' ($ms -ne '') ($m -replace "`n", ' / ')
Check 'T1 method target: the other members'' /// prose is NOT in the surface' (-not ($ms -match 'TwoDocProse|TwoParamProse')) ($ms -replace "`n", ' / ')
Check 'T2 method target: a // note line is NOT in the surface'                (-not ($ms -match 'LooseNoteProse')) ($ms -replace "`n", ' / ')
Check 'T3 method target: its own /// line is NOT repeated in the surface'     (-not ($ms -match 'OneDocProse')) ($ms -replace "`n", ' / ')
Check 'C1 CONTROL every member signature is still listed' `
      (($ms -match 'procedure One;') -and ($ms -match 'function Two\(A: Integer\): Integer;') -and ($ms -match 'procedure Three;')) ($ms -replace "`n", ' / ')
Check 'C2 CONTROL the target''s own doc is still in ## Doc' ((Section $m 'Doc') -match 'OneDocProse') ''

$ts = Section (Bundle 'modify uLean.TWorker') 'Class surface'
Check 'C3 CONTROL a TYPE target keeps the member docs' (($ts -match 'TwoDocProse') -and ($ts -match 'OneDocProse')) ($ts -replace "`n", ' / ')
$fs = Section (Bundle 'modify uLean.TWorker.One' -Full) 'Class surface'
Check 'C4 CONTROL --full-surface keeps the member docs' (($fs -match 'TwoDocProse') -and ($fs -match 'LooseNoteProse')) ($fs -replace "`n", ' / ')

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_context_member_surface_lean_$PID")) { if (Test-Path -LiteralPath $d23) { [IO.Directory]::Delete($d23, $true) } }
}
