<#
  run_with_hiding_rule.ps1 -- docs\PLAN-with-scope-refs-and-hiding.md, Part 2
  (owner request 2026-08-30).

  THE BUG CLASS, in the owner's words: inside `with`, a bare `Height`/`Width`
  silently binds to the with-target instead of the form he meant, and nothing
  warns. "I did spend a lot of time few months ago exactly because of such an
  error."

  IT SHIPS ENABLED AND NOISY ON HIS RULING -- the plan's 300-finding volume gate
  was WITHDRAWN. What was NOT withdrawn is precision, and that is what this
  guard is for: volume and wrongness are different failures. He accepted noise,
  not wrong findings. So most of the assertions below are SILENCE assertions,
  each paired with a firing one in the same run, because a rule that has died
  satisfies every silence check ever written.

  The four silencers, one fixture each: unresolvable with-target, name that is
  not a member of any layer, no provable outer declaration, and the TObject
  floor.

  KNOWN COVERAGE LIMIT, stated rather than discovered later: this guard indexes
  ONE project and passes no library store, so the CROSS-STORE half of the
  ancestry bridge (a project form descending TCustomForm) is not exercised here.
  The in-project ancestry walk IS -- TDerivedForm below inherits Width from a
  base class declared in another fixture unit. The cross-store hop is covered by
  the corpus measurement recorded in the plan, not by this runner.

  Run from a NEUTRAL CWD, pwsh 7.
#>
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-withhide"
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
$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir | Out-Null

function Emit([string]$name, [string]$text) {
  [System.IO.File]::WriteAllText((Join-Path $srcDir $name),
    (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

# --- the types every case draws on -----------------------------------------
Emit 'uWhTypes.pas' @'
unit uWhTypes;
interface
type
  TWhBaseForm = class
  public
    Width : Integer;
    Height: Integer;
    procedure Refresh;
  end;

  TWhPanel = class
  public
    Width : Integer;
    Caption: string;
    procedure Refresh;
  end;

  TWhCell = class
  public
    Width: Integer;
  end;

  TWhOnlyInner = class
  public
    Peculiar: Integer;
  end;

implementation
procedure TWhBaseForm.Refresh;
begin
end;
procedure TWhPanel.Refresh;
begin
end;
end.
'@

# LOCAL HIDDEN: the with-target has Width and so does the routine.
# SILENT SIBLING: Caption exists on the panel and nowhere outside.
Emit 'uWhLocal.pas' @'
unit uWhLocal;
interface
uses uWhTypes;
procedure LocalHidden(const APanel: TWhPanel);
procedure NoCollision(const APanel: TWhPanel);
implementation
procedure LocalHidden(const APanel: TWhPanel);
var
  Width: Integer;
begin
  Width:= 1;
  with APanel do
    Width:= 3;
end;
procedure NoCollision(const APanel: TWhPanel);
begin
  with APanel do
    Caption:= 'x';
end;
end.
'@

# SELF MEMBER THROUGH IN-PROJECT ANCESTRY: TWhDerivedForm inherits Width from
# TWhBaseForm, declared in ANOTHER unit, so this pins the transitive-ancestor
# walk and not just the class's own members.
Emit 'uWhSelf.pas' @'
unit uWhSelf;
interface
uses uWhTypes;
type
  TWhDerivedForm = class(TWhBaseForm)
  public
    FPanel: TWhPanel;
    FCell : TWhCell;
    procedure Resize;
    procedure Untouched;
  end;
implementation
procedure TWhDerivedForm.Resize;
begin
  with FPanel do
    Width:= 4;
end;
procedure TWhDerivedForm.Untouched;
begin
  with FPanel do
    Caption:= 'y';
end;
end.
'@

# MULTI-ITEM and NESTED. In `with ACell, APanel do` the panel is INNER, so
# Width binds to it and hides the cell's Width -- the layer order is the
# assertion. Peculiar is unique to the inner layer and must stay silent.
Emit 'uWhLayers.pas' @'
unit uWhLayers;
interface
uses uWhTypes;
procedure MultiItem(const ACell: TWhCell; const APanel: TWhPanel);
procedure InnerOnly(const ACell: TWhCell; const AOnly: TWhOnlyInner);
procedure Nested(const ACell: TWhCell; const APanel: TWhPanel);
implementation
procedure MultiItem(const ACell: TWhCell; const APanel: TWhPanel);
begin
  with ACell, APanel do
    Width:= 5;
end;
procedure InnerOnly(const ACell: TWhCell; const AOnly: TWhOnlyInner);
begin
  with ACell, AOnly do
    Peculiar:= 6;
end;
procedure Nested(const ACell: TWhCell; const APanel: TWhPanel);
begin
  with ACell do
    with APanel do
      Width:= 7;
end;
end.
'@

# THE SILENCERS: an unresolvable target, and the TObject floor.
Emit 'uWhSilent.pas' @'
unit uWhSilent;
interface
uses uWhTypes;
procedure Unresolvable(const AThing: TNotDeclaredAnywhere);
procedure ObjectFloor(const APanel: TWhPanel);
implementation
procedure Unresolvable(const AThing: TNotDeclaredAnywhere);
var
  Width: Integer;
begin
  Width:= 1;
  with AThing do
    Width:= 2;
end;
procedure ObjectFloor(const APanel: TWhPanel);
var
  Free: Integer;
begin
  Free:= 1;
  with APanel do
    Refresh;
end;
end.
'@

# --- index -----------------------------------------------------------------
$manifest = Join-Path $WorkDir 'manifest.drag-lint.json'
$mtext = '{' + [char]10 +
  '  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },' + [char]10 +
  '  "indexes": { "outDir": "out", "sections": [ { "name": "SecWh", "db": "wh.sqlite", "include": ["src"] } ] }' + [char]10 +
  '}'
[System.IO.File]::WriteAllText($manifest, $mtext, [System.Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'out\wh.sqlite'

$cfgOff = Join-Path $WorkDir 'off.json'
[System.IO.File]::WriteAllText($cfgOff, '{ "disabled": [ "with-hides-outer-symbol" ] }',
                               [System.Text.Encoding]::ASCII)

Push-Location C:\TEMP
try {
  & $Exe index --all --config $manifest --only SecWh --jobs 1 2>&1 | Out-Null
  if (-not (Test-Path $db)) {
    Write-Host "FATAL: index did not produce $db" -ForegroundColor Red; exit 2
  }
  $onOut  = & $Exe lint-all --db $db --quiet 2>&1 | Out-String
  $offOut = & $Exe lint-all --db $db --config $cfgOff --quiet 2>&1 | Out-String
} finally { Pop-Location }

$lines = @($onOut -split "`r?`n" | Where-Object { $_ -match 'with-hides-outer-symbol' })
function HitIn([string]$file, [string]$name) {
  @($lines | Where-Object { $_ -match [regex]::Escape($file) -and $_ -match ("'" + $name + "'") })
}

Write-Host ''
Write-Host 'THE FINDING' -ForegroundColor Cyan
$loc = HitIn 'uWhLocal.pas' 'Width'
Check 'LOCAL: a routine local hidden by the with-target is reported' ($loc.Count -eq 1) `
  ("got " + $loc.Count + " of " + $lines.Count + " total")
Check 'and it names the winning layer type' `
  (($loc -join ' ') -match 'TWhPanel') ''
Check 'and it names what is hidden' `
  (($loc -join ' ') -match 'local or parameter') ''
Check 'and it is a warning' (($loc -join ' ') -match '\[warning\]') ''
Check 'NO COLLISION: a member with no outer twin is SILENT' `
  ((HitIn 'uWhLocal.pas' 'Caption').Count -eq 0) `
  'RED means the rule fires on every with-member, not on hiding'

Write-Host ''
Write-Host 'ANCESTRY -- the hidden side is inherited from another unit' -ForegroundColor Cyan
$self = HitIn 'uWhSelf.pas' 'Width'
Check 'SELF: TWhDerivedForm.Width (inherited) is found as the hidden side' ($self.Count -eq 1) `
  ("got " + $self.Count)
Check 'and the message names the enclosing class' `
  (($self -join ' ') -match 'TWhDerivedForm') `
  'RED means the transitive-ancestor walk stopped at the class own members'
Check 'and its sibling routine stays SILENT' `
  ((HitIn 'uWhSelf.pas' 'Caption').Count -eq 0) ''

Write-Host ''
Write-Host 'LAYERS -- innermost wins, and the order is the assertion' -ForegroundColor Cyan
$multi  = HitIn 'uWhLayers.pas' 'Width'
Check 'MULTI-ITEM and NESTED both report Width' ($multi.Count -eq 2) `
  ("got " + $multi.Count + " (expect one per routine)")
Check 'the winner is the INNER layer (the panel), not the cell' `
  ((($multi -join ' ') -match 'TWhPanel') -and (-not (($multi -join ' ') -match 'binds to TWhCell'))) `
  'with A, B do resolves innermost-first; RED means the layer order is reversed'
Check 'and the hidden side is named as the outer layer' `
  (($multi -join ' ') -match 'outer with layer') ''
Check 'INNER-ONLY: a name only the inner layer has is SILENT' `
  ((HitIn 'uWhLayers.pas' 'Peculiar').Count -eq 0) `
  'nothing is hidden when no outer scope declares it'

Write-Host ''
Write-Host 'THE SILENCERS' -ForegroundColor Cyan
Check 'UNRESOLVABLE target -> SILENT even with a colliding local' `
  ((HitIn 'uWhSilent.pas' 'Width').Count -eq 0) `
  'no surface, no claim -- absence beats a guess'
Check 'TOBJECT FLOOR: Refresh/Free-class members do not fire' `
  ((HitIn 'uWhSilent.pas' 'Free').Count -eq 0) `
  'members of everything would make every with a finding'
Check 'POSITIVE CONTROL: the run that proves those silences is not empty' `
  ($lines.Count -ge 4) `
  ("only " + $lines.Count + " finding(s) -- the silences above prove nothing")

Write-Host ''
Write-Host 'OFF SWITCH' -ForegroundColor Cyan
Check 'a disabling config reports nothing' `
  (-not ($offOut -match 'with-hides-outer-symbol')) ''
Check 'POSITIVE CONTROL: the off run still produced other findings' `
  ($offOut -match ':\d+:\d+') `
  'a silent run would pass the check above for the wrong reason'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
