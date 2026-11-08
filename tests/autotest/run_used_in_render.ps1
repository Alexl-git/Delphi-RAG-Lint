<#
  run_used_in_render.ps1 -- E-USE-EDGES-PHASE2 rendering (wave 147 lane B1, spec
  docs\superpowers\specs\2026-09-14-use-edges-design.md sec 8, test T9). Owner
  ruling 2026-11-08 06:55: 'Used in:' ships DEFAULT ON in autodoc AND hover.

  THE GAP (measured on the deployed 1.46.0-alpha engine). A property or field
  that has RESOLVED uses (member_accesses rows: dotted, bare, Self., with) is
  documented with the name-matched 'Used by:' line -- no read/write mode, and
  the resolved entries are diluted with guesses. hover shows nothing about the
  uses at all.

  THE CONTRACT
    * a property/field with >= 1 resolved use renders ONE line
      'Used in: <routine> (<file>) [r|w|rw], ...' in the managed block, built
      from FindResolvedCallers' moded rows, one entry per routine, the modes of
      every site in that routine folded into [r], [w] or [rw];
    * that line REPLACES 'Used by:' on that symbol;
    * a routine keeps 'Called from:' and gets NO 'Used in:';
    * hover --format md and --format json carry the same line (the doc/hover
      consistency lock);
    * re-running document after a reindex is byte-identical (idempotent).

  CHECKS
    1  POSITIVE CONTROL: document writes a managed block with 'Called from:' on
       the routine TProvider.Work (green before the fix too; FATAL exit 2 when
       not -- the guard is not reading a document run)
    2  Value: 'Used in:' names uProv.TProvider.Work (uProv.pas) [rw]       (RED before)
    3  Value: 'Used in:' names uCons.TConsumer.Go (uCons.pas) [rw]         (RED before)
    4  Flag : Work [w] (bare write only) and Go [rw] (read C1, with-write C4) (RED before)
    5  Value/Flag carry NO 'Used by:' line (the resolved line replaces it)  (RED before)
    6  NEGATIVE: the routine Work has no 'Used in:' line
    7  NEGATIVE: Unused (a property nobody touches) has no 'Used in:' line
    8  hover --format md on Value carries 'Used in:'                       (RED before)
    9  hover --format json on Value: facts[] carries 'Used in:'            (RED before)
   10  idempotence: reindex + document again leaves uProv.pas byte-identical

  Line numbers are never hard-coded; the doc block is read back from the file.
  Usage: pwsh -File tests\autotest\run_used_in_render.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
. (Join-Path $PSScriptRoot 'exe-hint.ps1')
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if (-not $ok) { $script:fail = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ("draglint_used_in_render-{0}" -f $PID)
if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory $scratch | Out-Null

function W([string]$name, [string]$body) {
  [IO.File]::WriteAllText((Join-Path $scratch $name), ($body -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}
# The managed block (BEGIN..END lines, joined) directly above the declaration
# line that contains $decl; '' when that declaration has none.
function BlockAbove([string]$path, [string]$decl) {
  $lines = [IO.File]::ReadAllText($path) -split "`r`n"
  $at = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains($decl)) { $at = $i; break } }
  if ($at -lt 0) { return '' }
  $buf = @(); $j = $at - 1
  while ($j -ge 0 -and $lines[$j].TrimStart().StartsWith('///')) { $buf = ,$lines[$j] + $buf; $j-- }
  return ($buf -join "`n")
}
function Index([string]$db) {
  & $exePath index $scratch --db $db *> (Join-Path $scratch 'index.log')
  if ($LASTEXITCODE -ne 0) { $hint = Get-ExeStartFailureHint $LASTEXITCODE; if ($hint) { Write-Host "FATAL: $hint" -ForegroundColor Red }; Write-Host "FATAL: index exit $LASTEXITCODE" -ForegroundColor Red; exit 2 }
}

try {
  W 'uProv.pas' @'
unit uProv;

interface

type
  TProvider = class
  private
    FFlag: Boolean;
    FValue: Integer;
    FUnused: Integer;
    function GetValue: Integer;
    procedure SetValue(const pV: Integer);
  public
    procedure Work;
    property Flag: Boolean read FFlag write FFlag;
    property Value: Integer read GetValue write SetValue;
    property Unused: Integer read FUnused write FUnused;
  end;

implementation

function TProvider.GetValue: Integer;
begin
  Result := FValue;
end;

procedure TProvider.SetValue(const pV: Integer);
begin
  FValue := pV;
end;

procedure TProvider.Work;
var
  L: Integer;
begin
  Value := 5;
  L := Value;
  Flag := False;
  if L > 0 then
    L := 0;
end;

end.
'@
  W 'uCons.pas' @'
unit uCons;

interface

uses uProv;

type
  TConsumer = class
  private
    FProv: TProvider;
  public
    procedure Go;
  end;

implementation

procedure TConsumer.Go;
var
  N: Integer;
begin
  if FProv.Flag then
    FProv.Work;
  FProv.Value := 3;
  N := FProv.Value;
  with FProv do
    Flag := True;
  N := N + 1;
end;

end.
'@
  $fP = Join-Path $scratch 'uProv.pas'
  $db = Join-Path $scratch 'p.sqlite'
  # `document --unit` documents routines and types, not properties, so each
  # property goes through --qname; every apply shifts lines, so reindex first.
  Index $db
  Write-Host '== checks 8-9: hover (BEFORE any document run, so the line cannot come from a written doc block) ==' -ForegroundColor Cyan
  $md = (& $exePath hover --qname uProv.TProvider.Value --format md --db $db 2>$null) -join "`n"
  Check '8 hover md: Used in:' ($md -match 'Used in: [^\n]*uCons\.TConsumer\.Go \(uCons\.pas\) \[rw\]') $md
  $js = (& $exePath hover --qname uProv.TProvider.Value --format json --db $db 2>$null) -join "`n"
  $facts = @()
  try { $facts = @(($js | ConvertFrom-Json).facts) } catch { }
  Check '9 hover json: facts[] Used in:' (@($facts | Where-Object { ([string]$_).StartsWith('Used in: ') -and ([string]$_).Contains('[rw]') }).Count -eq 1) $js

  & $exePath document --unit $fP --db $db --apply --no-backup *> (Join-Path $scratch 'doc1.log')
  $ec = $LASTEXITCODE
  foreach ($q in 'Value', 'Flag', 'Unused') {
    Index $db
    & $exePath document --qname "uProv.TProvider.$q" --db $db --apply --no-backup *>> (Join-Path $scratch 'doc1.log')
    if ($LASTEXITCODE -ne 0) { $ec = $LASTEXITCODE }
  }

  $bWork  = BlockAbove $fP 'procedure Work;'
  $bValue = BlockAbove $fP 'property Value:'
  $bFlag  = BlockAbove $fP 'property Flag:'
  $bUnus  = BlockAbove $fP 'property Unused:'

  Write-Host '== check 1: POSITIVE CONTROL -- document wrote the routine block ==' -ForegroundColor Cyan
  $ok = ($ec -eq 0) -and $bWork.Contains('Called from: uCons.TConsumer.Go (uCons.pas)')
  Check '1 Work: Called from: uCons.TConsumer.Go' $ok "ec=$ec block=[$bWork]"
  if (-not $ok) { Write-Host 'FATAL: the document run did not produce the control block' -ForegroundColor Red; exit 2 }

  Write-Host '== checks 2-5: Used in: on a property ==' -ForegroundColor Cyan
  Check '2 Value: Work [rw]' ($bValue -match 'Used in: [^<]*uProv\.TProvider\.Work \(uProv\.pas\) \[rw\]') $bValue
  Check '3 Value: Go [rw]'   ($bValue -match 'Used in: [^<]*uCons\.TConsumer\.Go \(uCons\.pas\) \[rw\]') $bValue
  Check '4 Flag: Work [w] and Go [rw]' (($bFlag -match 'Used in: [^<]*uProv\.TProvider\.Work \(uProv\.pas\) \[w\]') -and ($bFlag -match 'Used in: [^<]*uCons\.TConsumer\.Go \(uCons\.pas\) \[rw\]')) $bFlag
  Check '5 Value/Flag: no Used by: line' ((-not $bValue.Contains('Used by:')) -and (-not $bFlag.Contains('Used by:')) -and ($bValue -ne '') -and ($bFlag -ne '')) "Value=[$bValue] Flag=[$bFlag]"

  Write-Host '== checks 6-7: NEGATIVE ==' -ForegroundColor Cyan
  Check '6 Work: no Used in: line' (-not $bWork.Contains('Used in:')) $bWork
  Check '7 Unused: no Used in: line' (-not $bUnus.Contains('Used in:')) $bUnus

  Write-Host '== check 10: idempotence ==' -ForegroundColor Cyan
  $before = [IO.File]::ReadAllBytes($fP)
  Index $db
  & $exePath document --qname uProv.TProvider.Value --db $db --apply --no-backup *> (Join-Path $scratch 'doc2.log')
  $after = [IO.File]::ReadAllBytes($fP)
  Check '10 second document run is byte-identical' (($LASTEXITCODE -eq 0) -and ([Convert]::ToBase64String($before) -eq [Convert]::ToBase64String($after))) (Get-Content (Join-Path $scratch 'doc2.log') -Raw)
}
finally {
  try { [IO.Directory]::Delete($scratch, $true) } catch { }
}
if ($script:fail) { Write-Host 'run_used_in_render: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_used_in_render: PASS' -ForegroundColor Green; exit 0
