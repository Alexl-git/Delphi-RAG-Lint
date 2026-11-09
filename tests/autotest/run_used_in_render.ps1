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

  WAVE 148 (lane UP) -- the two B1 leftovers, spec sec 8.1 bullet 2 + 8.2:
   11  getter GetValue: 'Called from:' kept AND 'Used in (via property Value):'
       names Work [r] and Go [r] (the property READS that run the getter)   (RED before)
   12  setter SetValue: 'Used in (via property Value):' names Work [w], Go [w] (RED before)
   13  hover --format md on GetValue carries 'Used in (via property Value):' (RED before)
   14  NEGATIVE: Work (no accessor) and the field-backed Flag carry no
       'Used in (via' line
   15  CROSS-DB: a property whose ONLY uses live in an EXTRA store (--db A
       --db B) renders 'Used in: uUser.TUser.Run (uUser.pas) [rw]', not the
       mode-less 'Used by:'                                                  (RED before)
   16  CROSS-DB echo: GetValue documented with --db A --db B names
       uUser.TUser.Run via property Value [r]                                (RED before)
   17  POSITIVE CONTROL for 15/16: the same document run with --db A alone
       writes no 'Used in' at all (A holds no use) -- so 15/16 can only pass
       through the extra store
   18  idempotence: reindex + document GetValue again is byte-identical (the
       via line is registered in ALL_LABELS and re-renders unchanged)

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
$scratchX = $scratch + '-x'   # the cross-DB fixture; outside $scratch, which Index walks whole
if (Test-Path $scratchX) { [IO.Directory]::Delete($scratchX, $true) }
New-Item -ItemType Directory $scratchX | Out-Null

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

  Write-Host '== checks 11-14: getter/setter echo line (spec sec 8.1 bullet 2) ==' -ForegroundColor Cyan
  Index $db
  $mdG = (& $exePath hover --qname uProv.TProvider.GetValue --format md --db $db 2>$null) -join "`n"
  foreach ($q in 'GetValue', 'SetValue') {
    Index $db
    & $exePath document --qname "uProv.TProvider.$q" --db $db --apply --no-backup *>> (Join-Path $scratch 'doc3.log')
  }
  $bGet  = BlockAbove $fP 'function GetValue:'
  $bSet  = BlockAbove $fP 'procedure SetValue('
  $bWork = BlockAbove $fP 'procedure Work;'
  $bFlag = BlockAbove $fP 'property Flag:'
  $via   = 'Used in \(via property Value\): [^<]*'
  Check '11 GetValue: Called from: kept + via Value Work [r], Go [r]' (
    $bGet.Contains('Called from:') -and
    ($bGet -match ($via + 'uProv\.TProvider\.Work \(uProv\.pas\) \[r\]')) -and
    ($bGet -match ($via + 'uCons\.TConsumer\.Go \(uCons\.pas\) \[r\]'))) $bGet
  Check '12 SetValue: via Value Work [w], Go [w]' (
    ($bSet -match ($via + 'uProv\.TProvider\.Work \(uProv\.pas\) \[w\]')) -and
    ($bSet -match ($via + 'uCons\.TConsumer\.Go \(uCons\.pas\) \[w\]'))) $bSet
  Check '13 hover md GetValue: Used in (via property Value):' ($mdG -match ($via + 'uCons\.TConsumer\.Go \(uCons\.pas\) \[r\]')) $mdG
  Check '14 Work / Flag: no via line' ((-not $bWork.Contains('Used in (via')) -and (-not $bFlag.Contains('Used in (via')) -and ($bFlag -ne '')) "Work=[$bWork] Flag=[$bFlag]"
  $before = [IO.File]::ReadAllBytes($fP)
  Index $db
  & $exePath document --qname uProv.TProvider.GetValue --db $db --apply --no-backup *> (Join-Path $scratch 'doc4.log')
  $after = [IO.File]::ReadAllBytes($fP)
  Check '18 idempotence: second document on GetValue is byte-identical' (($LASTEXITCODE -eq 0) -and $bGet.Contains('Used in (via') -and ([Convert]::ToBase64String($before) -eq [Convert]::ToBase64String($after))) (Get-Content (Join-Path $scratch 'doc4.log') -Raw)

  Write-Host '== checks 15-17: cross-DB (extra-store) uses ==' -ForegroundColor Cyan
  # A = the declaring unit alone (no use of any member); B = the same unit plus
  # a user. `document --db A --db B`: A primary, B extra (first --db wins).
  $xa = Join-Path $scratchX 'a'; $xb = Join-Path $scratchX 'b'
  New-Item -ItemType Directory $xa, $xb | Out-Null
  $provSrc = @'
unit uXProv;

interface

type
  TXProv = class
  private
    FFlag: Boolean;
    FValue: Integer;
    function GetValue: Integer;
  public
    property Flag: Boolean read FFlag write FFlag;
    property Value: Integer read GetValue;
  end;

implementation

function TXProv.GetValue: Integer;
begin
  Result := FValue;
end;

end.
'@ -replace "`r?`n", "`r`n"
  [IO.File]::WriteAllText((Join-Path $xa 'uXProv.pas'), $provSrc, [Text.Encoding]::ASCII)
  [IO.File]::WriteAllText((Join-Path $xb 'uXProv.pas'), $provSrc, [Text.Encoding]::ASCII)
  $userSrc = @'
unit uUser;

interface

uses uXProv;

type
  TUser = class
  private
    FP: TXProv;
  public
    procedure Run;
  end;

implementation

procedure TUser.Run;
var
  N: Integer;
begin
  if FP.Flag then
    FP.Flag := False;
  N := FP.Value;
  if N > 0 then
    N := 0;
end;

end.
'@ -replace "`r?`n", "`r`n"
  [IO.File]::WriteAllText((Join-Path $xb 'uUser.pas'), $userSrc, [Text.Encoding]::ASCII)
  $dbA = Join-Path $scratchX 'a.sqlite'; $dbB = Join-Path $scratchX 'b.sqlite'
  & $exePath index $xa --db $dbA *> (Join-Path $scratchX 'ia.log')
  & $exePath index $xb --db $dbB *> (Join-Path $scratchX 'ib.log')
  $fXA = Join-Path $xa 'uXProv.pas'
  $pristine = [IO.File]::ReadAllBytes($fXA)
  # 17 first: A alone.
  foreach ($q in 'Flag', 'GetValue') {
    & $exePath index $xa --db $dbA *>> (Join-Path $scratchX 'ia.log')
    & $exePath document --qname "uXProv.TXProv.$q" --db $dbA --apply --no-backup *>> (Join-Path $scratchX 'dA.log')
  }
  $aOnly = [IO.File]::ReadAllText($fXA)
  Check '17 POSITIVE CONTROL: --db A alone writes no Used in' (-not $aOnly.Contains('Used in')) $aOnly
  [IO.File]::WriteAllBytes($fXA, $pristine)
  foreach ($q in 'Flag', 'GetValue') {
    & $exePath index $xa --db $dbA *>> (Join-Path $scratchX 'ia.log')
    & $exePath document --qname "uXProv.TXProv.$q" --db $dbA --db $dbB --apply --no-backup *>> (Join-Path $scratchX 'dAB.log')
  }
  $bXFlag = BlockAbove $fXA 'property Flag:'
  $bXGet  = BlockAbove $fXA 'function GetValue:'
  Check '15 cross-DB Flag: Used in: uUser.TUser.Run [rw], no Used by:' (
    ($bXFlag -match 'Used in: [^<]*uUser\.TUser\.Run \(uUser\.pas\) \[rw\]') -and
    (-not $bXFlag.Contains('Used by:'))) $bXFlag
  Check '16 cross-DB GetValue: via property Value uUser.TUser.Run [r]' (
    $bXGet -match 'Used in \(via property Value\): [^<]*uUser\.TUser\.Run \(uUser\.pas\) \[r\]') $bXGet
}
finally {
  try { [IO.Directory]::Delete($scratch, $true) } catch { }
  try { [IO.Directory]::Delete($scratchX, $true) } catch { }
}
if ($script:fail) { Write-Host 'run_used_in_render: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_used_in_render: PASS' -ForegroundColor Green; exit 0
