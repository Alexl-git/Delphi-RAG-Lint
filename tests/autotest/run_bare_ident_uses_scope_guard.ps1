<#
  run_bare_ident_uses_scope_guard.ps1 -- a BARE identifier inside a method must
  not resolve to a unit the hovering file does not even use.

  THE DEFECT THIS PINS (owner, live IDE, 2026-08-19):

    C:\Projects\DataCopy\uMainZeissCopy.pas:4116
      if (WindowState = wsMinimized){ and (InitCount >= 2) } then

    "What type is WindowState? Why is it related to Tabc... when it is plain
     Windows type?"

    Measured before the fix:
      typeat ...:4116:9
        Resolved:  Abcutil.TabcLauncher.WindowState
        Signature: TabcShowWindowStyle

    `Abcutil` appears ZERO times in uMainZeissCopy.pas -- grep confirmed. The
    correct answer, `Vcl.Forms.TCustomForm.WindowState : TWindowState`, was
    sitting in the very same index.

  ROOT CAUSE. TTypeAtResolver.Resolve computes UsedUnits (the file's own uses)
  near the top, but applies it at exactly ONE call site -- the member-access
  branch, which is where the VCL/FMX fix landed on 2026-08-19. The BARE
  identifier branch checks the enclosing routine's params/locals and then falls
  straight to FindTypeAnywhere: a flat, whole-index, first-hit name lookup with
  no uses filter and no class scoping. So a bare member reference resolved to
  whichever same-named symbol the index happened to yield first.

  Why it is the worst shape of wrong: the answer NAMES A REAL TYPE and carries a
  REAL SIGNATURE, so nothing about it reads as a failure.

  THE CONTROLS:
    * The decoy unit is NOT used by the probe file, and the correct owner IS.
      Asserting only "resolves to the base" would pass against a resolver that
      always picked the first-indexed unit if the base happened to be indexed
      first -- so the decoy is indexed FIRST and named to sort FIRST.
    * A bare LOCAL VARIABLE must still win over both. That path already worked
      and must not regress: a uses filter applied too eagerly would break it.
    * A genuinely-unused-unit symbol must still resolve when it is the ONLY
      candidate -- the filter narrows, it must not blank out an answer that has
      no competition.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-bare-uses-scope"
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

# --- the DECOY: named to sort first, indexed first, NOT used by the probe ----
WriteAnsi (Join-Path $libDir 'aaaDecoyUnit.pas') @'
unit aaaDecoyUnit;

interface

type
  TDecoyStyle = (dsOne, dsTwo);

  TDecoyLauncher = class
  private
    FWindowStateZZ: TDecoyStyle;
  public
    property WindowStateZZ: TDecoyStyle read FWindowStateZZ write FWindowStateZZ;
  end;

implementation

end.
'@

# --- the CORRECT owner: a base class in a unit the probe file DOES use ------
WriteAnsi (Join-Path $libDir 'zzzBaseUnit.pas') @'
unit zzzBaseUnit;

interface

type
  TRealWindowState = (rwsNormal, rwsMinimized);

  TBaseFormLike = class
  private
    FWindowStateZZ: TRealWindowState;
  public
    property WindowStateZZ: TRealWindowState read FWindowStateZZ write FWindowStateZZ;
  end;

implementation

end.
'@

# --- the probe file: uses zzzBaseUnit ONLY, never aaaDecoyUnit --------------
WriteAnsi (Join-Path $appDir 'uProbeForm.pas') @'
unit uProbeForm;

interface

uses
  zzzBaseUnit;

type
  TMyForm = class(TBaseFormLike)
  public
    procedure RestoreWindow;
  end;

implementation

procedure TMyForm.RestoreWindow;
begin
  if WindowStateZZ = rwsMinimized then
    WindowStateZZ := rwsNormal;
end;

end.
'@

$libDb = Join-Path $WorkDir 'lib.sqlite'
$appDb = Join-Path $WorkDir 'app.sqlite'
& $Exe index $libDir --db $libDb 2>&1 | Out-Null
& $Exe index $appDir --db $appDb 2>&1 | Out-Null
Check 'both indexes built' ((Test-Path $libDb) -and (Test-Path $appDb))

$probe = Join-Path $appDir 'uProbeForm.pas'
$lines = [System.IO.File]::ReadAllLines($probe)
function LineNoOf([string]$needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains($needle)) { return ($i + 1) } }
  return -1
}

function TypeAt([int]$line1, [int]$col1) {
  $out = & $Exe typeat "${probe}:${line1}:${col1}" --db $appDb --db $libDb 2>$null | Out-String
  $r = ''
  foreach ($l in ($out -split "`r?`n")) {
    if ($l -match '^\s*Resolved:\s*(.+?)\s*$') { $r = $matches[1] }
  }
  return $r
}

# ---- THE DEFECT ------------------------------------------------------------
Write-Host ''
Write-Host 'THE DEFECT: a bare member reference must use the file own uses' -ForegroundColor Cyan
$ln  = LineNoOf 'if WindowStateZZ = rwsMinimized then'
$col = $lines[$ln - 1].IndexOf('WindowStateZZ') + 4
$got = TypeAt $ln $col
Check 'bare member resolves to the USED unit, not the decoy' ($got -eq 'zzzBaseUnit.TBaseFormLike.WindowStateZZ') `
  "resolved='$got'"
Check 'it is NOT the unit the file never uses' ($got -notmatch 'aaaDecoyUnit') "resolved='$got'"

# ---- CONTROL 1: a local of the same name still wins ------------------------
Write-Host ''
Write-Host 'CONTROLS' -ForegroundColor Cyan
# The local lives in its OWN unit. Put it beside RestoreWindow and the flat
# lookup finds THAT local for the probe above -- which is the same bug wearing a
# different hat, and it masked the contest under test on the first run.
$localProbe = Join-Path $appDir 'uLocalProbe.pas'
WriteAnsi $localProbe @'
unit uLocalProbe;

interface

uses
  zzzBaseUnit;

procedure WithLocal;

implementation

procedure WithLocal;
var
  WindowStateZZ: Integer;
begin
  WindowStateZZ := 1;
end;

end.
'@
& $Exe index $appDir --db $appDb 2>&1 | Out-Null
$lLines = [System.IO.File]::ReadAllLines($localProbe)
$lLn = -1
for ($i = 0; $i -lt $lLines.Count; $i++) { if ($lLines[$i].Contains('WindowStateZZ := 1;')) { $lLn = $i + 1; break } }
$lCol = $lLines[$lLn - 1].IndexOf('WindowStateZZ') + 4
$lOut = & $Exe typeat "${localProbe}:${lLn}:${lCol}" --db $appDb --db $libDb 2>$null | Out-String
$got2 = ''
foreach ($l in ($lOut -split "`r?`n")) { if ($l -match '^\s*Resolved:\s*(.+?)\s*$') { $got2 = $matches[1] } }
Check 'CONTROL: a bare LOCAL of the same name still beats both units' ($got2 -match 'WithLocal') "resolved='$got2'"

# ---- CONTROL 2: an uncontested symbol from an unused unit still resolves ---
# TDecoyStyle exists ONLY in the decoy unit. The uses filter must NARROW a
# contested lookup, never blank out an answer that has no competition.
$soloProbe = Join-Path $appDir 'uSolo.pas'
WriteAnsi $soloProbe @'
unit uSolo;

interface

uses
  zzzBaseUnit;

procedure Go;

implementation

procedure Go;
begin
  Writeln(TDecoyStyle);
end;

end.
'@
& $Exe index $appDir --db $appDb 2>&1 | Out-Null
$sLines = [System.IO.File]::ReadAllLines($soloProbe)
$sLn = -1
for ($i = 0; $i -lt $sLines.Count; $i++) { if ($sLines[$i].Contains('Writeln(TDecoyStyle)')) { $sLn = $i + 1; break } }
$sCol = $sLines[$sLn - 1].IndexOf('TDecoyStyle') + 4
$sOut = & $Exe typeat "${soloProbe}:${sLn}:${sCol}" --db $appDb --db $libDb 2>$null | Out-String
$sGot = ''
foreach ($l in ($sOut -split "`r?`n")) { if ($l -match '^\s*Resolved:\s*(.+?)\s*$') { $sGot = $matches[1] } }
Check 'CONTROL: an UNCONTESTED symbol from an unused unit still resolves' ($sGot -match 'TDecoyStyle') `
  "resolved='$sGot'"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
